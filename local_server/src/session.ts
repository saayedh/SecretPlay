import { WebSocket } from 'ws';
import crypto from 'crypto';
import {
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
  MessageAck,
} from './protocols/protocol';

const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');
const MAX_AUTH_SKEW_MS = 60_000;
const RATE_LIMIT_WINDOW_MS = 10_000;
const RATE_LIMIT_MAX_FRAMES = 60;
const SERVER_TOKEN_TTL_MS = 15 * 60 * 1000;

export interface DeviceConnection {
  deviceId: string;
  ws: WebSocket;
  publicKey?: string;
  lastPing: number;
}

export interface PairingInvitation {
  invitationCode: string;
  deviceAId: string;
  deviceAPublicKey: string;
  expiresAt: number;
}

export class SessionManager {
  private activeDevices: Map<string, DeviceConnection> = new Map();
  private pairedDevices: {
    deviceAId?: string;
    deviceAPublicKey?: string;
    deviceBId?: string;
    deviceBPublicKey?: string;
    isPaired: boolean;
    isRevoked: boolean;
  } = { isPaired: false, isRevoked: false };

  private activeInvitation: PairingInvitation | null = null;
  private sessionEpoch: string | null = null;
  private heartbeatInterval: NodeJS.Timeout | null = null;
  private seenNonces: Map<string, number> = new Map();
  private rateWindows: Map<string, number[]> = new Map();

  private serverToken: string;
  private serverTokenExpiresAt: number;

  private readonly timeoutMs: number;
  private readonly heartbeatMs: number;

  constructor(timeoutMs = 20000, heartbeatMs = 5000) {
    this.timeoutMs = timeoutMs;
    this.heartbeatMs = heartbeatMs;
    this.serverToken = crypto.randomBytes(16).toString('hex');
    this.serverTokenExpiresAt = Date.now() + SERVER_TOKEN_TTL_MS;
    this.startHeartbeatMonitor();
  }

  public getOrRotateServerToken(): { token: string; expiresAt: number } {
    if (Date.now() >= this.serverTokenExpiresAt) {
      this.serverToken = crypto.randomBytes(16).toString('hex');
      this.serverTokenExpiresAt = Date.now() + SERVER_TOKEN_TTL_MS;
    }
    return {
      token: this.serverToken,
      expiresAt: this.serverTokenExpiresAt,
    };
  }

  private startHeartbeatMonitor(): void {
    this.heartbeatInterval = setInterval(() => {
      const now = Date.now();
      for (const [deviceId, dev] of this.activeDevices.entries()) {
        if (now - dev.lastPing > this.timeoutMs) {
          console.warn(`[LocalServer] Heartbeat timeout for device: ${deviceId}`);
          this.terminateSession(deviceId, 'timeout');
        }
      }
    }, this.heartbeatMs);
  }

  public getStatus() {
    const tokenInfo = this.getOrRotateServerToken();
    return {
      isPaired: this.pairedDevices.isPaired,
      isRevoked: this.pairedDevices.isRevoked,
      deviceA: this.pairedDevices.deviceAId || null,
      deviceB: this.pairedDevices.deviceBId || null,
      activeSession: this.sessionEpoch !== null,
      sessionEpoch: this.sessionEpoch,
      connectedDevices: Array.from(this.activeDevices.keys()),
      hasPendingInvitation: this.activeInvitation !== null,
      serverTokenExpiresAt: tokenInfo.expiresAt,
    };
  }

  public checkRateLimit(ws: WebSocket, deviceId: string): boolean {
    const now = Date.now();
    const history = this.rateWindows.get(deviceId) ?? [];
    const recent = history.filter((ts) => now - ts < RATE_LIMIT_WINDOW_MS);
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
    for (const [k, exp] of this.seenNonces.entries()) {
      if (exp <= now) {
        this.seenNonces.delete(k);
      }
    }
    if (this.seenNonces.has(nonce)) {
      return false;
    }
    this.seenNonces.set(nonce, now + MAX_AUTH_SKEW_MS * 2);
    return true;
  }

  private verifyOptionalEd25519Signature(
    registeredPubKeyBase64: string | undefined,
    payload: string,
    signatureBase64: string
  ): boolean {
    if (!registeredPubKeyBase64) return true;
    let rawPub: Buffer;
    try {
      rawPub = Buffer.from(registeredPubKeyBase64, 'base64');
    } catch {
      return true;
    }
    // Enforce cryptographic Ed25519 signature check when a 32-byte or 64-byte raw public key is registered
    if (rawPub.length !== 32 && rawPub.length !== 64) {
      return true;
    }
    try {
      const edRaw = rawPub.subarray(0, 32);
      const pubKeyObj = crypto.createPublicKey({
        key: Buffer.concat([ED25519_SPKI_PREFIX, edRaw]),
        format: 'der',
        type: 'spki',
      });
      const sigBuf = Buffer.from(signatureBase64, 'base64');
      if (sigBuf.length !== 64) {
        return false;
      }
      return crypto.verify(null, Buffer.from(payload, 'utf8'), pubKeyObj, sigBuf);
    } catch {
      return false;
    }
  }

  public handleAuth(ws: WebSocket, msg: AuthMessage): void {
    const now = Date.now();
    const deviceId = msg.deviceId;

    if (this.pairedDevices.isRevoked) {
      const err: AuthResultMessage = {
        type: 'auth_result',
        version: 1,
        success: false,
        deviceId,
        peerConnected: false,
        error: 'Pair has been revoked. Re-pairing required.',
        timestamp: now,
      };
      ws.send(JSON.stringify(err));
      ws.close(1008, 'Revoked');
      return;
    }

    if (!Number.isFinite(msg.timestamp) || Math.abs(now - msg.timestamp) > MAX_AUTH_SKEW_MS) {
      const err: AuthResultMessage = {
        type: 'auth_result',
        version: 1,
        success: false,
        deviceId,
        peerConnected: false,
        error: 'Authentication timestamp outside allowed window.',
        timestamp: now,
      };
      ws.send(JSON.stringify(err));
      ws.close(1008, 'Auth timestamp expired');
      return;
    }

    if (!msg.nonce || !this.recordNonce(`${deviceId}:${msg.nonce}`, now)) {
      const err: AuthResultMessage = {
        type: 'auth_result',
        version: 1,
        success: false,
        deviceId,
        peerConnected: false,
        error: 'Replayed or missing authentication nonce.',
        timestamp: now,
      };
      ws.send(JSON.stringify(err));
      ws.close(1008, 'Auth replay');
      return;
    }

    let registeredPubKey: string | undefined;

    // Automatic two-device token binding (TOFU) when publicKey is supplied
    if (!this.pairedDevices.isRevoked && msg.publicKey && msg.publicKey.length >= 16) {
      if (!this.pairedDevices.deviceAId || this.pairedDevices.deviceAId === deviceId) {
        this.pairedDevices.deviceAId = deviceId;
        this.pairedDevices.deviceAPublicKey = msg.publicKey;
      } else if (!this.pairedDevices.deviceBId || this.pairedDevices.deviceBId === deviceId) {
        this.pairedDevices.deviceBId = deviceId;
        this.pairedDevices.deviceBPublicKey = msg.publicKey;
        this.pairedDevices.isPaired = true;
      }
    }

    // Check if pairing state allows this connection
    if (!this.pairedDevices.isPaired) {
      if (this.pairedDevices.deviceAId === deviceId) {
        registeredPubKey = this.pairedDevices.deviceAPublicKey;
      } else if (this.activeInvitation && this.activeInvitation.deviceAId === deviceId) {
        registeredPubKey = this.activeInvitation.deviceAPublicKey;
      } else {
        const err: AuthResultMessage = {
          type: 'auth_result',
          version: 1,
          success: false,
          deviceId,
          peerConnected: false,
          error: 'Devices not paired yet. Please complete QR pairing first.',
          timestamp: now,
        };
        ws.send(JSON.stringify(err));
        ws.close(1008, 'Unpaired');
        return;
      }
    } else {
      // Must be Device A or Device B
      if (deviceId === this.pairedDevices.deviceAId) {
        registeredPubKey = this.pairedDevices.deviceAPublicKey;
      } else if (deviceId === this.pairedDevices.deviceBId) {
        registeredPubKey = this.pairedDevices.deviceBPublicKey;
      } else {
        console.warn(`[LocalServer] Unauthorized device connection rejected: ${deviceId}`);
        const err: AuthResultMessage = {
          type: 'auth_result',
          version: 1,
          success: false,
          deviceId,
          peerConnected: false,
          error: 'Unauthorized device - maximum 2 authorized devices enforced.',
          timestamp: now,
        };
        ws.send(JSON.stringify(err));
        ws.close(1008, 'Unauthorized 3rd device');
        return;
      }
    }

    const sigOk = this.verifyOptionalEd25519Signature(
      registeredPubKey,
      `${deviceId}:${msg.nonce}:${msg.timestamp}`,
      msg.signature
    );
    if (!sigOk) {
      const err: AuthResultMessage = {
        type: 'auth_result',
        version: 1,
        success: false,
        deviceId,
        peerConnected: false,
        error: 'Invalid Ed25519 authentication signature.',
        timestamp: now,
      };
      ws.send(JSON.stringify(err));
      ws.close(1008, 'Invalid signature');
      return;
    }

    // Register active device
    this.activeDevices.set(deviceId, {
      deviceId,
      ws,
      publicKey: registeredPubKey,
      lastPing: now,
    });

    const peerId = this.getPeerId(deviceId);
    const peerPubKey =
      deviceId === this.pairedDevices.deviceAId
        ? this.pairedDevices.deviceBPublicKey
        : deviceId === this.pairedDevices.deviceBId
          ? this.pairedDevices.deviceAPublicKey
          : undefined;
    const peerConnected = peerId ? this.activeDevices.has(peerId) : false;

    // When both devices are connected, create new session epoch
    if (peerConnected && !this.sessionEpoch) {
      this.sessionEpoch = crypto.randomUUID();
      console.log(`[LocalServer] Active mutual session established! Epoch: ${this.sessionEpoch}`);
    }

    const res: AuthResultMessage = {
      type: 'auth_result',
      version: 1,
      success: true,
      deviceId,
      peerConnected,
      sessionEpoch: this.sessionEpoch || undefined,
      peerDeviceId: peerId || undefined,
      peerPublicKey: peerPubKey,
      pairToken: msg.pairToken,
      timestamp: now,
    };
    ws.send(JSON.stringify(res));

    // Notify peer
    if (peerId && this.activeDevices.has(peerId)) {
      const statusMsg: SessionStatusMessage = {
        type: 'session_status',
        version: 1,
        active: Boolean(this.sessionEpoch),
        peerOnline: true,
        sessionEpoch: this.sessionEpoch || '',
        peerDeviceId: deviceId,
        peerPublicKey: registeredPubKey,
        timestamp: now,
      };
      this.activeDevices.get(peerId)!.ws.send(JSON.stringify(statusMsg));
    }
  }

  public handlePing(ws: WebSocket, deviceId: string): void {
    const dev = this.activeDevices.get(deviceId);
    if (dev) {
      dev.lastPing = Date.now();
    }
    ws.send(JSON.stringify({ type: 'pong', version: 1, timestamp: Date.now() }));
  }

  public handleMessage(ws: WebSocket, msg: EncryptedChatMessage): void {
    if (!this.sessionEpoch || msg.sessionEpoch !== this.sessionEpoch) {
      console.warn(`[LocalServer] Dropped message with stale/invalid session epoch`);
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

    const recipient = this.activeDevices.get(msg.recipientDeviceId);
    if (!recipient) {
      // Discard immediately: Zero offline storage policy
      const ack: MessageAck = {
        type: 'msg_ack',
        version: 1,
        msgId: msg.msgId,
        status: 'dropped_peer_offline',
        timestamp: Date.now(),
      };
      ws.send(JSON.stringify(ack));
      return;
    }

    // Direct memory relay to recipient
    recipient.ws.send(JSON.stringify(msg));

    const ack: MessageAck = {
      type: 'msg_ack',
      version: 1,
      msgId: msg.msgId,
      status: 'relayed',
      timestamp: Date.now(),
    };
    ws.send(JSON.stringify(ack));
  }

  public handleSignaling(ws: WebSocket, signal: SignalingMessage): void {
    if (!this.sessionEpoch || signal.sessionEpoch !== this.sessionEpoch) {
      return;
    }

    const recipient = this.activeDevices.get(signal.recipientDeviceId);
    if (recipient) {
      recipient.ws.send(JSON.stringify(signal));
    }
  }

  public handlePairingInit(ws: WebSocket, msg: PairingInitMessage): void {
    if (this.pairedDevices.isPaired) {
      const resp: PairingConfirmMessage = {
        type: 'pairing_confirm',
        version: 1,
        success: false,
        error: 'System is already paired. Reset server or revoke existing pair first.',
        timestamp: Date.now(),
      };
      ws.send(JSON.stringify(resp));
      return;
    }

    this.pairedDevices.isRevoked = false;
    this.activeInvitation = {
      invitationCode: msg.invitationCode,
      deviceAId: msg.deviceAId,
      deviceAPublicKey: msg.deviceAPublicKey,
      expiresAt: Date.now() + 5 * 60 * 1000,
    };

    this.activeDevices.set(msg.deviceAId, {
      deviceId: msg.deviceAId,
      ws,
      publicKey: msg.deviceAPublicKey,
      lastPing: Date.now(),
    });

    console.log(`[LocalServer] Pairing initiated by Device A (${msg.deviceAId}).`);

    const resp: PairingConfirmMessage = {
      type: 'pairing_confirm',
      version: 1,
      success: true,
      timestamp: Date.now(),
    };
    ws.send(JSON.stringify(resp));
  }

  public handlePairingClaim(ws: WebSocket, msg: PairingClaimMessage): void {
    if (!this.activeInvitation) {
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

    if (Date.now() > this.activeInvitation.expiresAt) {
      this.activeInvitation = null;
      ws.send(
        JSON.stringify({
          type: 'pairing_confirm',
          version: 1,
          success: false,
          error: 'Pairing invitation expired',
          timestamp: Date.now(),
        })
      );
      return;
    }

    if (this.activeInvitation.invitationCode !== msg.invitationCode) {
      ws.send(
        JSON.stringify({
          type: 'pairing_confirm',
          version: 1,
          success: false,
          error: 'Invalid pairing invitation code',
          timestamp: Date.now(),
        })
      );
      return;
    }

    if (msg.deviceBId === this.activeInvitation.deviceAId) {
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

    const deviceAId = this.activeInvitation.deviceAId;
    const deviceAPubKey = this.activeInvitation.deviceAPublicKey;

    // Complete pairing
    this.pairedDevices = {
      deviceAId,
      deviceAPublicKey: deviceAPubKey,
      deviceBId: msg.deviceBId,
      deviceBPublicKey: msg.deviceBPublicKey,
      isPaired: true,
      isRevoked: false,
    };

    this.activeInvitation = null;

    this.activeDevices.set(msg.deviceBId, {
      deviceId: msg.deviceBId,
      ws,
      publicKey: msg.deviceBPublicKey,
      lastPing: Date.now(),
    });

    this.sessionEpoch = crypto.randomUUID();
    console.log(`[LocalServer] Device pairing complete between ${deviceAId} and ${msg.deviceBId}`);

    const now = Date.now();
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

    ws.send(JSON.stringify(confirmForB));
    const devA = this.activeDevices.get(deviceAId);
    if (devA) {
      devA.ws.send(JSON.stringify(confirmForA));
    }
  }

  public handleRevoke(ws: WebSocket, msg: RevokePairMessage): void {
    const now = Date.now();
    if (!this.pairedDevices.isPaired) {
      ws.send(
        JSON.stringify({
          type: 'revoke_confirm',
          version: 1,
          success: false,
          error: 'No active pair to revoke',
          timestamp: now,
        } satisfies RevokeConfirmMessage)
      );
      return;
    }

    if (
      msg.senderDeviceId !== this.pairedDevices.deviceAId &&
      msg.senderDeviceId !== this.pairedDevices.deviceBId
    ) {
      ws.close(1008, 'Unauthorized revocation sender');
      return;
    }

    const registeredPub =
      msg.senderDeviceId === this.pairedDevices.deviceAId
        ? this.pairedDevices.deviceAPublicKey
        : this.pairedDevices.deviceBPublicKey;

    if (
      !this.verifyOptionalEd25519Signature(
        registeredPub,
        `${msg.senderDeviceId}:${msg.nonce}:${msg.timestamp}`,
        msg.signature
      )
    ) {
      ws.send(
        JSON.stringify({
          type: 'revoke_confirm',
          version: 1,
          success: false,
          error: 'Invalid signature for revocation',
          timestamp: now,
        } satisfies RevokeConfirmMessage)
      );
      return;
    }

    this.pairedDevices = { isPaired: false, isRevoked: true };
    this.activeInvitation = null;
    this.sessionEpoch = null;

    const confirm: RevokeConfirmMessage = {
      type: 'revoke_confirm',
      version: 1,
      success: true,
      revokedBy: msg.senderDeviceId,
      timestamp: now,
    };

    for (const dev of this.activeDevices.values()) {
      try {
        dev.ws.send(JSON.stringify(confirm));
        dev.ws.close(1000, 'Pair revoked');
      } catch {
        // Ignore send errors
      }
    }
    this.activeDevices.clear();
  }

  public terminateSession(initiatorDeviceId: string, reason: string): void {
    console.log(`[LocalServer] Session terminated by ${initiatorDeviceId}. Reason: ${reason}`);

    const termMsg: TerminateSessionMessage = {
      type: 'terminate',
      version: 1,
      reason: reason as TerminateSessionMessage['reason'],
      senderDeviceId: initiatorDeviceId,
      timestamp: Date.now(),
    };

    for (const [, dev] of this.activeDevices.entries()) {
      try {
        dev.ws.send(JSON.stringify(termMsg));
        dev.ws.close(1000, `Session Terminated: ${reason}`);
      } catch {
        // Ignore close error
      }
    }

    // Completely wipe session from memory
    this.activeDevices.clear();
    this.sessionEpoch = null;
  }

  public handleSocketClose(ws: WebSocket): void {
    let closedDeviceId: string | null = null;
    for (const [id, dev] of this.activeDevices.entries()) {
      if (dev.ws === ws) {
        closedDeviceId = id;
        break;
      }
    }

    if (closedDeviceId) {
      console.log(`[LocalServer] Device disconnected: ${closedDeviceId}`);
      this.terminateSession(closedDeviceId, 'peer_disconnected');
    }
  }

  public resetPairing(): void {
    this.pairedDevices = { isPaired: false, isRevoked: false };
    this.activeInvitation = null;
    this.sessionEpoch = null;
    this.activeDevices.clear();
    this.seenNonces.clear();
    console.log(`[LocalServer] Pairing and sessions have been reset.`);
  }

  private getPeerId(deviceId: string): string | null {
    if (deviceId === this.pairedDevices.deviceAId) return this.pairedDevices.deviceBId || null;
    if (deviceId === this.pairedDevices.deviceBId) return this.pairedDevices.deviceAId || null;
    return null;
  }

  public dispose(): void {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
  }
}
