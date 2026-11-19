import { DurableObject } from 'cloudflare:workers';
import {
  SecretPlayMessage,
  AuthMessage,
  AuthResultMessage,
  SessionStatusMessage,
  EncryptedChatMessage,
  SignalingMessage,
  TerminateSessionMessage,
  PairingInitMessage,
  PairingClaimMessage,
  PairingConfirmMessage,
  RevokePairMessage,
  RevokeConfirmMessage,
} from '../protocols/protocol';

interface Env {
  SESSION_RELAY: DurableObjectNamespace;
}

interface DeviceState {
  deviceId: string;
  ws: WebSocket;
  lastSeen: number;
}

interface SocketAttachment {
  deviceId: string;
  authenticatedAt: number;
  sessionEpoch?: string | null;
}

interface PairRecord {
  id: number;
  pair_id: string;
  device_a_id: string | null;
  device_a_pubkey: string | null;
  device_b_id: string | null;
  device_b_pubkey: string | null;
  is_paired: number;
  is_revoked: number;
  updated_at: number;
}

const MAX_AUTH_SKEW_MS = 60_000;
const RATE_LIMIT_WINDOW_MS = 10_000;
const RATE_LIMIT_MAX_FRAMES = 60;
const MAX_SEEN_NONCES = 1024;
const PAIRING_TTL_MS = 5 * 60 * 1000;

function decodeBase64(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export class SecretPlaySessionRelay extends DurableObject {
  // Volatile in-memory state - Never persisted to storage
  private activeDevices: Map<string, DeviceState> = new Map();
  private sessionEpoch: string | null = null;
  private pairingInvitation: {
    token: string;
    deviceAId: string;
    deviceAPubKey: string;
    expiresAt: number;
  } | null = null;
  private seenNonces: Map<string, number> = new Map();
  private rateWindows: Map<string, number[]> = new Map();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.initStorage();
  }

  private initStorage(): void {
    // SQLite table only for minimal device authorization & pairing metadata.
    // Zero message data or session keys are ever saved to disk.
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS pair_identity (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        pair_id TEXT NOT NULL,
        device_a_id TEXT,
        device_a_pubkey TEXT,
        device_b_id TEXT,
        device_b_pubkey TEXT,
        is_paired INTEGER DEFAULT 0,
        is_revoked INTEGER DEFAULT 0,
        updated_at INTEGER NOT NULL
      );
    `);
  }

  private getPairRecord(): PairRecord | null {
    const cursor = this.ctx.storage.sql.exec('SELECT * FROM pair_identity WHERE id = 1');
    const rows = [...cursor] as unknown as PairRecord[];
    return rows.length > 0 ? rows[0] : null;
  }

  private getSocketDeviceId(ws: WebSocket): string | null {
    try {
      const attachment = ws.deserializeAttachment() as SocketAttachment | null;
      if (attachment && typeof attachment.deviceId === 'string' && attachment.deviceId.length > 0) {
        return attachment.deviceId;
      }
    } catch {
      // Fallback to tags if attachment is unavailable
    }
    try {
      const tags = this.ctx.getTags(ws);
      if (tags.length > 0) return tags[0];
    } catch {
      // Ignore if tags not supported
    }
    for (const [id, state] of this.activeDevices.entries()) {
      if (state.ws === ws) return id;
    }
    return null;
  }

  private attachDeviceToSocket(ws: WebSocket, deviceId: string, sessionEpoch?: string | null): void {
    const attachment: SocketAttachment = {
      deviceId,
      authenticatedAt: Date.now(),
      sessionEpoch: sessionEpoch ?? this.sessionEpoch,
    };
    ws.serializeAttachment(attachment);
    this.activeDevices.set(deviceId, { deviceId, ws, lastSeen: Date.now() });
  }

  private getConnectedSocketMap(): Map<string, WebSocket> {
    const result = new Map<string, WebSocket>();
    for (const [id, state] of this.activeDevices.entries()) {
      result.set(id, state.ws);
    }
    try {
      const hibernatedSockets = this.ctx.getWebSockets();
      const restoredEpochs: string[] = [];
      for (const ws of hibernatedSockets) {
        const deviceId = this.getSocketDeviceId(ws);
        if (deviceId && !result.has(deviceId)) {
          result.set(deviceId, ws);
          this.activeDevices.set(deviceId, { deviceId, ws, lastSeen: Date.now() });
        }
        try {
          const att = ws.deserializeAttachment() as SocketAttachment | null;
          if (att?.sessionEpoch) {
            restoredEpochs.push(att.sessionEpoch);
          }
        } catch {
          // Ignore malformed attachment
        }
      }
      // Recover ephemeral epoch after DO hibernation ONLY when both live WebSockets agree on it
      if (!this.sessionEpoch && result.size === 2 && restoredEpochs.length === 2 && restoredEpochs[0] === restoredEpochs[1]) {
        this.sessionEpoch = restoredEpochs[0];
      }
    } catch {
      // Ignore if mock doesn't implement getWebSockets
    }
    return result;
  }

  private syncEpochToAttachments(sockets: Map<string, WebSocket>, epoch: string | null): void {
    for (const [deviceId, sock] of sockets.entries()) {
      try {
        const prev = (sock.deserializeAttachment() as SocketAttachment | null) ?? {
          deviceId,
          authenticatedAt: Date.now(),
        };
        sock.serializeAttachment({ ...prev, deviceId, sessionEpoch: epoch });
      } catch {
        // Ignore if attachment update fails
      }
    }
  }

  private checkRateLimit(ws: WebSocket, deviceId: string): boolean {
    const now = Date.now();
    const timestamps = this.rateWindows.get(deviceId) ?? [];
    const recent = timestamps.filter((ts) => now - ts < RATE_LIMIT_WINDOW_MS);
    if (recent.length >= RATE_LIMIT_MAX_FRAMES) {
      ws.send(
        JSON.stringify({
          type: 'terminate',
          version: 1,
          reason: 'security_alert',
          senderDeviceId: 'server',
          timestamp: now,
        })
      );
      ws.close(1008, 'Rate limit exceeded');
      return false;
    }
    recent.push(now);
    this.rateWindows.set(deviceId, recent);
    return true;
  }

  private recordNonce(nonce: string, now: number): boolean {
    for (const [key, exp] of this.seenNonces.entries()) {
      if (exp <= now) {
        this.seenNonces.delete(key);
      }
    }
    if (this.seenNonces.has(nonce)) {
      return false;
    }
    while (this.seenNonces.size >= MAX_SEEN_NONCES) {
      const oldest = this.seenNonces.keys().next().value;
      if (oldest === undefined) break;
      this.seenNonces.delete(oldest);
    }
    this.seenNonces.set(nonce, now + MAX_AUTH_SKEW_MS * 2);
    return true;
  }

  private async verifyDeviceSignature(
    registeredPubKeyBase64: string | null,
    payloadText: string,
    signatureBase64: string
  ): Promise<boolean> {
    if (!registeredPubKeyBase64) return false;
    let rawPub: Uint8Array;
    try {
      rawPub = decodeBase64(registeredPubKeyBase64);
    } catch {
      return false;
    }
    // Enforce cryptographic proof whenever a valid 32B Ed25519 or 64B combined key is registered
    if (rawPub.length !== 32 && rawPub.length !== 64) {
      return false;
    }
    try {
      const ed25519Raw = rawPub.subarray(0, 32);
      const sigBytes = decodeBase64(signatureBase64);
      if (sigBytes.length !== 64) {
        return false;
      }
      const key = await crypto.subtle.importKey(
        'raw',
        ed25519Raw,
        { name: 'Ed25519' },
        false,
        ['verify']
      );
      const data = new TextEncoder().encode(payloadText);
      return await crypto.subtle.verify({ name: 'Ed25519' }, key, sigBytes, data);
    } catch {
      return false;
    }
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // Health check endpoint
    if (url.pathname === '/health') {
      const pair = this.getPairRecord();
      const sockets = this.getConnectedSocketMap();
      return Response.json({
        status: 'healthy',
        isPaired: pair ? Boolean(pair.is_paired) : false,
        isRevoked: pair ? Boolean(pair.is_revoked) : false,
        activeSession: this.sessionEpoch !== null,
        connectedDevices: sockets.size,
        timestamp: Date.now(),
      });
    }

    // Explicit revocation endpoint
    if (url.pathname === '/revoke' && request.method === 'POST') {
      await this.revokePair('admin_http');
      return Response.json({
        success: true,
        revoked: true,
        timestamp: Date.now(),
      });
    }

    // WebSocket upgrade
    if (request.headers.get('Upgrade')?.toLowerCase() === 'websocket') {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);

      // Accept with WebSocket hibernation enabled
      this.ctx.acceptWebSocket(server);

      return new Response(null, {
        status: 101,
        webSocket: client,
      });
    }

    return new Response('SecretPlay Relay Endpoint', { status: 200 });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== 'string') {
      return; // Reject binary payloads directly; protocol uses JSON text envelopes
    }

    let parsed: SecretPlayMessage;
    try {
      parsed = JSON.parse(message) as SecretPlayMessage;
    } catch {
      ws.send(
        JSON.stringify({
          type: 'terminate',
          version: 1,
          reason: 'security_alert',
          senderDeviceId: 'server',
          timestamp: Date.now(),
        })
      );
      ws.close(1008, 'Malformed JSON');
      return;
    }

    const senderId = this.getSocketDeviceId(ws);
    if (senderId && parsed.type !== 'auth' && !this.checkRateLimit(ws, senderId)) {
      return;
    }

    switch (parsed.type) {
      case 'ping':
        this.handlePing(ws);
        break;

      case 'auth':
        await this.handleAuth(ws, parsed as AuthMessage);
        break;

      case 'msg':
        this.handleEncryptedMessage(ws, parsed as EncryptedChatMessage);
        break;

      case 'signal':
        this.handleSignaling(ws, parsed as SignalingMessage);
        break;

      case 'terminate':
        this.handleTerminate(ws, parsed as TerminateSessionMessage);
        break;

      case 'pairing_init':
        this.handlePairingInit(ws, parsed as PairingInitMessage);
        break;

      case 'pairing_claim':
        this.handlePairingClaim(ws, parsed as PairingClaimMessage);
        break;

      case 'revoke':
        await this.handleRevoke(ws, parsed as RevokePairMessage);
        break;

      default:
        // Ignore unrecognized message types
        break;
    }
  }

  private handlePing(ws: WebSocket): void {
    const deviceId = this.getSocketDeviceId(ws);
    if (deviceId && this.activeDevices.has(deviceId)) {
      this.activeDevices.get(deviceId)!.lastSeen = Date.now();
    }
    ws.send(JSON.stringify({ type: 'pong', version: 1, timestamp: Date.now() }));
  }

  private async handleAuth(ws: WebSocket, authMsg: AuthMessage): Promise<void> {
    const now = Date.now();
    const pair = this.getPairRecord();
    const deviceId = authMsg.deviceId;

    // Reject revoked pairs
    if (pair && pair.is_revoked) {
      const rej: AuthResultMessage = {
        type: 'auth_result',
        version: 1,
        success: false,
        deviceId,
        peerConnected: false,
        error: 'Pair has been revoked',
        timestamp: now,
      };
      ws.send(JSON.stringify(rej));
      ws.close(1008, 'Revoked');
      return;
    }

    // Validate timestamp skew and replay nonce
    if (!Number.isFinite(authMsg.timestamp) || Math.abs(now - authMsg.timestamp) > MAX_AUTH_SKEW_MS) {
      const rej: AuthResultMessage = {
        type: 'auth_result',
        version: 1,
        success: false,
        deviceId,
        peerConnected: false,
        error: 'Authentication timestamp outside allowed window',
        timestamp: now,
      };
      ws.send(JSON.stringify(rej));
      ws.close(1008, 'Auth timestamp expired');
      return;
    }

    if (!authMsg.nonce || !this.recordNonce(authMsg.nonce, now)) {
      const rej: AuthResultMessage = {
        type: 'auth_result',
        version: 1,
        success: false,
        deviceId,
        peerConnected: false,
        error: 'Replayed or missing authentication nonce',
        timestamp: now,
      };
      ws.send(JSON.stringify(rej));
      ws.close(1008, 'Auth replay');
      return;
    }

    // Check device authorization against registered 2 slots
    let pairRecord = pair;
    let isAuthorized = false;
    let peerDeviceId: string | null = null;
    let peerPublicKey: string | null = null;
    let registeredPubKey: string | null = null;

    // Automatic two-device token room binding (TOFU) when publicKey is supplied
    if (authMsg.publicKey && authMsg.publicKey.length >= 32) {
      if (!pairRecord) {
        this.ctx.storage.sql.exec(
          `INSERT OR REPLACE INTO pair_identity
           (id, pair_id, device_a_id, device_a_pubkey, device_b_id, device_b_pubkey, is_paired, is_revoked, updated_at)
           VALUES (1, ?, ?, ?, NULL, NULL, 0, 0, ?);`,
          authMsg.pairToken || 'token-room',
          deviceId,
          authMsg.publicKey,
          now
        );
        pairRecord = this.getPairRecord();
      } else if (!pairRecord.is_paired && !pairRecord.is_revoked) {
        if (!pairRecord.device_a_id || pairRecord.device_a_id === deviceId) {
          this.ctx.storage.sql.exec(
            `UPDATE pair_identity SET device_a_id = ?, device_a_pubkey = ?, updated_at = ? WHERE id = 1;`,
            deviceId,
            authMsg.publicKey,
            now
          );
          pairRecord = this.getPairRecord();
        } else if (!pairRecord.device_b_id || pairRecord.device_b_id === deviceId) {
          this.ctx.storage.sql.exec(
            `UPDATE pair_identity SET device_b_id = ?, device_b_pubkey = ?, is_paired = 1, updated_at = ? WHERE id = 1;`,
            deviceId,
            authMsg.publicKey,
            now
          );
          pairRecord = this.getPairRecord();
        }
      }
    }

    if (!pairRecord || !pairRecord.is_paired) {
      if (pairRecord && pairRecord.device_a_id === deviceId) {
        isAuthorized = true;
        registeredPubKey = pairRecord.device_a_pubkey;
      } else if (this.pairingInvitation && this.pairingInvitation.deviceAId === deviceId) {
        isAuthorized = true;
        registeredPubKey = this.pairingInvitation.deviceAPubKey;
      }
    } else {
      if (pairRecord.device_a_id === deviceId) {
        isAuthorized = true;
        peerDeviceId = pairRecord.device_b_id;
        peerPublicKey = pairRecord.device_b_pubkey;
        registeredPubKey = pairRecord.device_a_pubkey;
      } else if (pairRecord.device_b_id === deviceId) {
        isAuthorized = true;
        peerDeviceId = pairRecord.device_a_id;
        peerPublicKey = pairRecord.device_a_pubkey;
        registeredPubKey = pairRecord.device_b_pubkey;
      }
    }

    if (!isAuthorized) {
      const rej: AuthResultMessage = {
        type: 'auth_result',
        version: 1,
        success: false,
        deviceId,
        peerConnected: false,
        error: 'Unauthorized device - maximum 2 authorized devices enforced',
        timestamp: now,
      };
      ws.send(JSON.stringify(rej));
      ws.close(1008, 'Unauthorized device');
      return;
    }

    // Verify Ed25519 signature over `${deviceId}:${nonce}:${timestamp}`
    const sigOk = await this.verifyDeviceSignature(
      registeredPubKey,
      `${deviceId}:${authMsg.nonce}:${authMsg.timestamp}`,
      authMsg.signature
    );
    if (!sigOk) {
      const rej: AuthResultMessage = {
        type: 'auth_result',
        version: 1,
        success: false,
        deviceId,
        peerConnected: false,
        error: 'Invalid device Ed25519 authentication signature',
        timestamp: now,
      };
      ws.send(JSON.stringify(rej));
      ws.close(1008, 'Invalid signature');
      return;
    }

    // Attach identity to WebSocket for hibernation recovery
    this.attachDeviceToSocket(ws, deviceId);

    const sockets = this.getConnectedSocketMap();
    const peerSocket = peerDeviceId ? sockets.get(peerDeviceId) : undefined;
    const peerConnected = Boolean(peerSocket);

    // If both devices are now connected, establish new ephemeral session epoch
    if (peerConnected && !this.sessionEpoch) {
      this.sessionEpoch = crypto.randomUUID();
      this.syncEpochToAttachments(sockets, this.sessionEpoch);
    } else if (this.sessionEpoch) {
      this.attachDeviceToSocket(ws, deviceId, this.sessionEpoch);
    }

    const authRes: AuthResultMessage = {
      type: 'auth_result',
      version: 1,
      success: true,
      deviceId,
      peerConnected,
      sessionEpoch: this.sessionEpoch || undefined,
      peerDeviceId: peerDeviceId || undefined,
      peerPublicKey: peerPublicKey || undefined,
      pairToken: authMsg.pairToken,
      timestamp: now,
    };
    ws.send(JSON.stringify(authRes));

    // Notify peer if online (including our deviceId and publicKey for automatic E2EE key pinning)
    if (peerSocket) {
      const statusMsg: SessionStatusMessage = {
        type: 'session_status',
        version: 1,
        active: Boolean(this.sessionEpoch),
        peerOnline: true,
        sessionEpoch: this.sessionEpoch || '',
        peerDeviceId: deviceId,
        peerPublicKey: registeredPubKey || undefined,
        timestamp: now,
      };
      try {
        peerSocket.send(JSON.stringify(statusMsg));
      } catch {
        if (peerDeviceId) {
          this.activeDevices.delete(peerDeviceId);
        }
      }
    }
  }

  private handleEncryptedMessage(ws: WebSocket, msg: EncryptedChatMessage): void {
    const senderDeviceId = this.getSocketDeviceId(ws);

    // Authenticate sender
    if (!senderDeviceId || senderDeviceId !== msg.senderDeviceId) {
      ws.send(
        JSON.stringify({
          type: 'terminate',
          version: 1,
          reason: 'security_alert',
          senderDeviceId: 'server',
          timestamp: Date.now(),
        })
      );
      return;
    }

    const sockets = this.getConnectedSocketMap();

    // Enforce active session epoch
    if (!this.sessionEpoch || msg.sessionEpoch !== this.sessionEpoch) {
      ws.send(
        JSON.stringify({
          type: 'terminate',
          version: 1,
          reason: 'security_alert',
          senderDeviceId: 'server',
          timestamp: Date.now(),
        })
      );
      return;
    }

    // Relay ONLY to the other paired device if connected
    const recipient = sockets.get(msg.recipientDeviceId);
    if (!recipient || msg.recipientDeviceId === senderDeviceId) {
      // Discard immediately: Zero offline storage policy
      ws.send(
        JSON.stringify({
          type: 'msg_ack',
          version: 1,
          msgId: msg.msgId,
          status: 'dropped_peer_offline',
          timestamp: Date.now(),
        })
      );
      return;
    }

    // Forward ciphertext in memory directly to recipient
    recipient.send(JSON.stringify(msg));

    // Send delivery confirmation ack to sender
    ws.send(
      JSON.stringify({
        type: 'msg_ack',
        version: 1,
        msgId: msg.msgId,
        status: 'relayed',
        timestamp: Date.now(),
      })
    );
  }

  private handleSignaling(ws: WebSocket, signal: SignalingMessage): void {
    const senderDeviceId = this.getSocketDeviceId(ws);

    if (!senderDeviceId || senderDeviceId !== signal.senderDeviceId) {
      return;
    }

    const sockets = this.getConnectedSocketMap();

    if (!this.sessionEpoch || signal.sessionEpoch !== this.sessionEpoch) {
      return;
    }

    // Forward signaling payload to peer
    const recipient = sockets.get(signal.recipientDeviceId);
    if (recipient && signal.recipientDeviceId !== senderDeviceId) {
      recipient.send(JSON.stringify(signal));
    }
  }

  private handleTerminate(ws: WebSocket, msg: TerminateSessionMessage): void {
    const senderDeviceId = this.getSocketDeviceId(ws);
    const sockets = this.getConnectedSocketMap();

    // Inform peer of termination
    for (const [dId, peerWs] of sockets.entries()) {
      if (dId !== senderDeviceId) {
        try {
          peerWs.send(JSON.stringify(msg));
        } catch {
          // Ignore send errors on closing sockets
        }
      }
    }

    // Wipe ephemeral session state from memory and socket attachments
    this.sessionEpoch = null;
    this.syncEpochToAttachments(sockets, null);
    this.activeDevices.clear();
  }

  private handlePairingInit(ws: WebSocket, msg: PairingInitMessage): void {
    const existing = this.getPairRecord();
    if (existing && existing.is_paired) {
      ws.send(
        JSON.stringify({
          type: 'pairing_confirm',
          version: 1,
          success: false,
          error: 'Pair already established. Revocation required before re-pairing.',
          timestamp: Date.now(),
        })
      );
      return;
    }

    // Generate high-entropy pairing invitation (valid for 5 minutes)
    this.pairingInvitation = {
      token: msg.invitationCode,
      deviceAId: msg.deviceAId,
      deviceAPubKey: msg.deviceAPublicKey,
      expiresAt: Date.now() + PAIRING_TTL_MS,
    };

    this.attachDeviceToSocket(ws, msg.deviceAId);

    ws.send(
      JSON.stringify({
        type: 'pairing_confirm',
        version: 1,
        success: true,
        timestamp: Date.now(),
      })
    );
  }

  private handlePairingClaim(ws: WebSocket, msg: PairingClaimMessage): void {
    if (!this.pairingInvitation) {
      ws.send(
        JSON.stringify({
          type: 'pairing_confirm',
          version: 1,
          success: false,
          error: 'No active pairing invitation found',
          timestamp: Date.now(),
        })
      );
      return;
    }

    if (Date.now() > this.pairingInvitation.expiresAt) {
      this.pairingInvitation = null;
      ws.send(
        JSON.stringify({
          type: 'pairing_confirm',
          version: 1,
          success: false,
          error: 'Pairing invitation has expired',
          timestamp: Date.now(),
        })
      );
      return;
    }

    if (this.pairingInvitation.token !== msg.invitationCode) {
      ws.send(
        JSON.stringify({
          type: 'pairing_confirm',
          version: 1,
          success: false,
          error: 'Invalid pairing token',
          timestamp: Date.now(),
        })
      );
      return;
    }

    const existing = this.getPairRecord();
    if (existing && existing.is_paired) {
      this.pairingInvitation = null;
      ws.send(
        JSON.stringify({
          type: 'pairing_confirm',
          version: 1,
          success: false,
          error: 'Pair already established',
          timestamp: Date.now(),
        })
      );
      return;
    }

    if (msg.deviceBId === this.pairingInvitation.deviceAId) {
      ws.send(
        JSON.stringify({
          type: 'pairing_confirm',
          version: 1,
          success: false,
          error: 'Device B must have a distinct identity from Device A',
          timestamp: Date.now(),
        })
      );
      return;
    }

    // Commit pairing to SQLite metadata storage
    const now = Date.now();
    this.ctx.storage.sql.exec(
      `
      INSERT OR REPLACE INTO pair_identity
      (id, pair_id, device_a_id, device_a_pubkey, device_b_id, device_b_pubkey, is_paired, is_revoked, updated_at)
      VALUES (1, ?, ?, ?, ?, ?, 1, 0, ?);
    `,
      'pair-primary',
      this.pairingInvitation.deviceAId,
      this.pairingInvitation.deviceAPubKey,
      msg.deviceBId,
      msg.deviceBPublicKey,
      now
    );

    // Clean up temporary one-time invitation immediately
    const deviceAId = this.pairingInvitation.deviceAId;
    const deviceAPubKey = this.pairingInvitation.deviceAPubKey;
    this.pairingInvitation = null;

    // Register device B
    this.attachDeviceToSocket(ws, msg.deviceBId);

    // Establish session epoch
    this.sessionEpoch = crypto.randomUUID();
    const sockets = this.getConnectedSocketMap();
    this.syncEpochToAttachments(sockets, this.sessionEpoch);

    const confirmForB: PairingConfirmMessage = {
      type: 'pairing_confirm',
      version: 1,
      success: true,
      peerDeviceId: deviceAId,
      peerPublicKey: deviceAPubKey,
      sessionEpoch: this.sessionEpoch,
      timestamp: now,
    };

    const confirmForA: PairingConfirmMessage = {
      type: 'pairing_confirm',
      version: 1,
      success: true,
      peerDeviceId: msg.deviceBId,
      peerPublicKey: msg.deviceBPublicKey,
      sessionEpoch: this.sessionEpoch,
      timestamp: now,
    };

    // Notify both devices with each other's public identities so both compute SAS
    ws.send(JSON.stringify(confirmForB));
    const devAWs = sockets.get(deviceAId);
    if (devAWs) {
      devAWs.send(JSON.stringify(confirmForA));
    }
  }

  private async handleRevoke(ws: WebSocket, msg: RevokePairMessage): Promise<void> {
    const senderDeviceId = this.getSocketDeviceId(ws);
    const pair = this.getPairRecord();

    if (!pair || !pair.is_paired) {
      ws.send(
        JSON.stringify({
          type: 'revoke_confirm',
          version: 1,
          success: false,
          error: 'No active pair to revoke',
          timestamp: Date.now(),
        } satisfies RevokeConfirmMessage)
      );
      return;
    }

    if (!senderDeviceId || senderDeviceId !== msg.senderDeviceId) {
      ws.close(1008, 'Unauthorized revocation sender');
      return;
    }

    const registeredPubKey =
      pair.device_a_id === senderDeviceId
        ? pair.device_a_pubkey
        : pair.device_b_id === senderDeviceId
          ? pair.device_b_pubkey
          : null;

    const sigOk = await this.verifyDeviceSignature(
      registeredPubKey,
      `${senderDeviceId}:${msg.nonce}:${msg.timestamp}`,
      msg.signature
    );
    if (!sigOk) {
      ws.send(
        JSON.stringify({
          type: 'revoke_confirm',
          version: 1,
          success: false,
          error: 'Invalid signature for revocation',
          timestamp: Date.now(),
        } satisfies RevokeConfirmMessage)
      );
      return;
    }

    await this.revokePair(senderDeviceId);
  }

  private async revokePair(revokedBy: string): Promise<void> {
    const now = Date.now();
    this.ctx.storage.sql.exec(
      `UPDATE pair_identity SET is_paired = 0, is_revoked = 1, updated_at = ? WHERE id = 1;`,
      now
    );

    const sockets = this.getConnectedSocketMap();
    const confirm: RevokeConfirmMessage = {
      type: 'revoke_confirm',
      version: 1,
      success: true,
      revokedBy,
      timestamp: now,
    };

    for (const sock of sockets.values()) {
      try {
        sock.send(JSON.stringify(confirm));
        sock.close(1000, 'Pair revoked');
      } catch {
        // Ignore already-closed sockets
      }
    }

    this.pairingInvitation = null;
    this.sessionEpoch = null;
    this.activeDevices.clear();
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    const deviceId = this.getSocketDeviceId(ws);
    try {
      ws.serializeAttachment(null);
    } catch {
      // Ignore attachment clear error
    }

    if (deviceId) {
      this.activeDevices.delete(deviceId);
      // Ending any socket invalidates the mutual session epoch immediately
      this.sessionEpoch = null;

      const sockets = this.getConnectedSocketMap();
      sockets.delete(deviceId);
      this.syncEpochToAttachments(sockets, null);
      for (const peerWs of sockets.values()) {
        if (peerWs === ws) continue;
        try {
          peerWs.send(
            JSON.stringify({
              type: 'session_status',
              version: 1,
              active: false,
              peerOnline: false,
              sessionEpoch: '',
              timestamp: Date.now(),
            })
          );
        } catch {
          // Ignore send errors
        }
      }
    }
  }

  async webSocketError(ws: WebSocket, error: unknown): Promise<void> {
    try {
      ws.close(1011, 'WebSocket internal error');
    } catch {
      // Ignore close error
    }
  }
}
