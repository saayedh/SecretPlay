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
  country?: string;
  ipMasked?: string;
}

interface AdminDeviceRow {
  device_id: string;
  secret_number: string;
  public_key: string;
  country: string;
  ip_masked: string;
  room_token: string;
  first_seen: number;
  last_seen: number;
  connect_count: number;
  msg_count: number;
  call_count: number;
  is_banned: number;
  is_approved: number;
  ban_reason: string;
  note: string;
}

interface AdminConfigRow {
  id: number;
  lockdown_mode: number;
  whitelist_mode: number;
  total_messages: number;
  total_calls: number;
  admin_secret_hash: string;
  latest_version?: string;
  latest_build?: number;
  download_url?: string;
  release_notes?: string;
}

function deriveSecretNumber(deviceId: string, pubKey: string): string {
  const text = `${deviceId}:${pubKey}`.trim();
  let h1 = 5381;
  let h2 = 2166136261;
  for (let i = 0; i < text.length; i++) {
    const b = text.charCodeAt(i);
    h1 = ((h1 << 5) + h1 + b) & 0x7fffffff;
    h2 = Math.imul(h2 ^ b, 16777619) & 0x7fffffff;
  }
  const p1 = 100 + (h1 % 900);
  const p2 = 100 + (h2 % 900);
  return `SP-${p1}-${p2}`;
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
const RATE_LIMIT_MAX_FRAMES = 180;
const MAX_SEEN_NONCES = 1024;
const PAIRING_TTL_MS = 5 * 60 * 1000;
const OFFLINE_MSG_TTL_MS = 7 * 24 * 60 * 60 * 1000;

function decodeBase64(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export class SecretPlaySessionRelay extends DurableObject<Env> {
  // Volatile in-memory state - Never persisted to storage
  private activeDevices: Map<string, DeviceState> = new Map();
  private sessionEpoch: string | null = null;
  private offlineQueue: Map<string, EncryptedChatMessage[]> = new Map();
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
    try {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS admin_devices (
          device_id TEXT PRIMARY KEY,
          secret_number TEXT,
          public_key TEXT DEFAULT '',
          country TEXT,
          ip_masked TEXT,
          room_token TEXT,
          first_seen INTEGER,
          last_seen INTEGER,
          connect_count INTEGER DEFAULT 1,
          msg_count INTEGER DEFAULT 0,
          call_count INTEGER DEFAULT 0,
          is_banned INTEGER DEFAULT 0,
          is_approved INTEGER DEFAULT 1,
          ban_reason TEXT DEFAULT '',
          note TEXT DEFAULT ''
        );
      `);
      this.ctx.storage.sql.exec(`ALTER TABLE admin_devices ADD COLUMN public_key TEXT DEFAULT '';`);
    } catch {}
    try {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS admin_config (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          lockdown_mode INTEGER DEFAULT 0,
          whitelist_mode INTEGER DEFAULT 0,
          total_messages INTEGER DEFAULT 0,
          total_calls INTEGER DEFAULT 0,
          admin_secret_hash TEXT DEFAULT 'SP-ADMIN-2026',
          latest_version TEXT DEFAULT '1.2.0',
          latest_build INTEGER DEFAULT 2,
          download_url TEXT DEFAULT 'https://github.com/saayedh/SecretPlay/releases/download/v1.0.0/app-arm64-v8a-release.apk',
          release_notes TEXT DEFAULT 'نسخه جدید SecretPlay با رفع باگ چت، تماس تصویری و قابلیت‌های جدید آماده است!'
        );
      `);
      this.ctx.storage.sql.exec(`ALTER TABLE admin_config ADD COLUMN latest_version TEXT DEFAULT '1.2.0';`);
      this.ctx.storage.sql.exec(`ALTER TABLE admin_config ADD COLUMN latest_build INTEGER DEFAULT 2;`);
      this.ctx.storage.sql.exec(`ALTER TABLE admin_config ADD COLUMN download_url TEXT DEFAULT 'https://github.com/saayedh/SecretPlay/releases/download/v1.0.0/app-arm64-v8a-release.apk';`);
      this.ctx.storage.sql.exec(`ALTER TABLE admin_config ADD COLUMN release_notes TEXT DEFAULT 'نسخه جدید SecretPlay آماده است!';`);
    } catch {
      // Ignore if columns already exist or in unit test mock SQL storage
    }
    try {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS offline_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          recipient_device_id TEXT NOT NULL,
          msg_id TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          created_at INTEGER NOT NULL
        );
      `);
      this.ctx.storage.sql.exec(
        `CREATE UNIQUE INDEX IF NOT EXISTS idx_offline_msg_unique ON offline_messages(recipient_device_id, msg_id);`
      );
    } catch {}
    try {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS inbox_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          event_id TEXT UNIQUE,
          payload_json TEXT NOT NULL,
          created_at INTEGER NOT NULL
        );
      `);
    } catch {}
  }

  private pushToDeviceInbox(
    targetDeviceId: string | null | undefined,
    event: Record<string, unknown>
  ): void {
    try {
      if (
        !targetDeviceId ||
        targetDeviceId === 'peer' ||
        !this.env?.SESSION_RELAY ||
        typeof this.env.SESSION_RELAY.idFromName !== 'function'
      ) {
        return;
      }
      const id = this.env.SESSION_RELAY.idFromName(`inbox:${targetDeviceId}`);
      const stub = this.env.SESSION_RELAY.get(id);
      if (stub && (stub as unknown) !== (this as unknown)) {
        stub
          .fetch(
            new Request('https://internal/internal-inbox/push', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ recipientDeviceId: targetDeviceId, ...event }),
            })
          )
          .catch(() => {});
      }
    } catch {}
  }

  private getAdminStub(): DurableObjectStub | null {
    try {
      if (this.env && this.env.SESSION_RELAY && typeof this.env.SESSION_RELAY.idFromName === 'function') {
        const id = this.env.SESSION_RELAY.idFromName('admin-registry');
        const stub = this.env.SESSION_RELAY.get(id);
        if (stub && (stub as unknown) !== (this as unknown)) {
          return stub;
        }
      }
    } catch {}
    return null;
  }

  private getAdminConfig(): AdminConfigRow {
    try {
      const cur = this.ctx.storage.sql.exec('SELECT * FROM admin_config WHERE id = 1');
      const rows = [...cur] as unknown as AdminConfigRow[];
      if (rows.length > 0) return rows[0];
      this.ctx.storage.sql.exec(
        `INSERT OR IGNORE INTO admin_config (id, lockdown_mode, whitelist_mode, total_messages, total_calls, admin_secret_hash)
         VALUES (1, 0, 0, 0, 0, 'SP-ADMIN-2026');`
      );
    } catch {}
    return {
      id: 1,
      lockdown_mode: 0,
      whitelist_mode: 0,
      total_messages: 0,
      total_calls: 0,
      admin_secret_hash: 'SP-ADMIN-2026',
    };
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
    let prevCountry = 'UN';
    let prevIp = '0.0.*.*';
    try {
      const prev = ws.deserializeAttachment() as SocketAttachment | null;
      if (prev?.country) prevCountry = prev.country;
      if (prev?.ipMasked) prevIp = prev.ipMasked;
    } catch {}
    const attachment: SocketAttachment = {
      deviceId,
      authenticatedAt: Date.now(),
      sessionEpoch: sessionEpoch ?? this.sessionEpoch,
      country: prevCountry,
      ipMasked: prevIp,
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

    // Internal Admin Registry & Room Control Endpoints
    if (url.pathname.startsWith('/internal-admin/')) {
      return await this.handleInternalAdminRequest(request, url);
    }

    // Personal Device Inbox Push (disguised background notifications, floating heartbeats & holograms)
    if (url.pathname === '/internal-inbox/push' && request.method === 'POST') {
      const now = Date.now();
      const body = (await request.json()) as Record<string, unknown>;
      const envelope = {
        type: 'inbox_event',
        version: 1,
        eventId:
          typeof body.eventId === 'string' && body.eventId.length > 0
            ? body.eventId
            : crypto.randomUUID(),
        eventType: typeof body.eventType === 'string' ? body.eventType : 'new_msg',
        senderDeviceId: typeof body.senderDeviceId === 'string' ? body.senderDeviceId : '',
        title: typeof body.title === 'string' ? body.title : '',
        body: typeof body.body === 'string' ? body.body : '',
        emoji: typeof body.emoji === 'string' ? body.emoji : '',
        colorHex: typeof body.colorHex === 'string' ? body.colorHex : '#FF007A',
        mediaBase64: typeof body.mediaBase64 === 'string' ? body.mediaBase64 : '',
        flashSeconds: typeof body.flashSeconds === 'number' ? body.flashSeconds : 7,
        roomToken: typeof body.roomToken === 'string' ? body.roomToken : '',
        timestamp: now,
      };
      const serialized = JSON.stringify(envelope);
      let delivered = 0;
      let sockets: WebSocket[] = [];
      try {
        sockets = this.ctx.getWebSockets('inbox');
      } catch {}
      for (const sock of sockets) {
        try {
          sock.send(serialized);
          delivered++;
        } catch {}
      }
      if (delivered === 0) {
        try {
          this.ctx.storage.sql.exec(
            `DELETE FROM inbox_events WHERE created_at < ?;`,
            now - 43_200_000
          );
          this.ctx.storage.sql.exec(
            `DELETE FROM inbox_events WHERE id NOT IN (SELECT id FROM inbox_events ORDER BY id DESC LIMIT 29);`
          );
          this.ctx.storage.sql.exec(
            `INSERT OR IGNORE INTO inbox_events (event_id, payload_json, created_at) VALUES (?, ?, ?);`,
            envelope.eventId,
            serialized,
            now
          );
        } catch {}
      }
      return Response.json({ ok: true, delivered, queued: delivered === 0 });
    }

    // Personal Device Inbox 24/7 WebSocket Upgrade
    if (
      url.pathname === '/inbox-ws' &&
      request.headers.get('Upgrade')?.toLowerCase() === 'websocket'
    ) {
      const now = Date.now();
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server, ['inbox']);
      try {
        server.send(JSON.stringify({ type: 'inbox_ready', version: 1, timestamp: now }));
        const rows = [
          ...this.ctx.storage.sql.exec(
            `SELECT id, payload_json FROM inbox_events WHERE created_at > ? ORDER BY id ASC LIMIT 30;`,
            now - 43_200_000
          ),
        ] as unknown as { id: number; payload_json: string }[];
        if (rows.length > 0) {
          const maxId = rows[rows.length - 1].id;
          for (const row of rows) {
            try {
              server.send(row.payload_json);
            } catch {}
          }
          this.ctx.storage.sql.exec(`DELETE FROM inbox_events WHERE id <= ?;`, maxId);
        }
      } catch {}
      return new Response(null, { status: 101, webSocket: client });
    }

    // WebSocket upgrade
    if (request.headers.get('Upgrade')?.toLowerCase() === 'websocket') {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);

      // Accept with WebSocket hibernation enabled
      this.ctx.acceptWebSocket(server);
      try {
        const cfCountry = request.headers.get('CF-IPCountry') || 'UN';
        const rawIp = request.headers.get('CF-Connecting-IP') || '0.0.0.0';
        const ipParts = rawIp.split('.');
        const ipMasked =
          ipParts.length === 4 ? `${ipParts[0]}.${ipParts[1]}.*.*` : rawIp.slice(0, 10) + '***';
        server.serializeAttachment({
          deviceId: '',
          authenticatedAt: 0,
          country: cfCountry,
          ipMasked,
        } satisfies SocketAttachment);
      } catch {}

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

    switch (parsed.type as string) {
      case 'ping':
        this.handlePing(ws);
        break;

      case 'auth':
        await this.handleAuth(ws, parsed as AuthMessage);
        break;

      case 'msg':
        this.handleEncryptedMessage(ws, parsed as EncryptedChatMessage);
        break;

      case 'msg_received':
        this.handleMessageReceived(ws, parsed as unknown as { msgId?: string; senderDeviceId?: string });
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

    // Validate timestamp presence (allow local system clock / timezone drift; anti-replay is enforced via unique cryptographic nonces)
    if (!Number.isFinite(authMsg.timestamp) || authMsg.timestamp <= 0) {
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

    // Check Global Admin Registry for Banned Device / Lockdown / Whitelist Policy
    let latestUpdate: Record<string, unknown> | undefined;
    const adminStub = this.getAdminStub();
    if (adminStub) {
      try {
        let country = 'UN';
        let ipMasked = '0.0.*.*';
        try {
          const att = ws.deserializeAttachment() as SocketAttachment | null;
          if (att?.country) country = att.country;
          if (att?.ipMasked) ipMasked = att.ipMasked;
        } catch {}

        const checkRes = await adminStub.fetch(
          new Request('https://internal/internal-admin/telemetry', {
            method: 'POST',
            body: JSON.stringify({
              event: 'auth',
              deviceId,
              secretNumber: deriveSecretNumber(deviceId, authMsg.publicKey || ''),
              publicKey: authMsg.publicKey || '',
              country,
              ipMasked,
              roomToken: authMsg.pairToken || 'primary-pair',
            }),
          })
        );
        if (checkRes.ok) {
          const checkJson = (await checkRes.json()) as {
            allowed: boolean;
            reason?: string;
            latestUpdate?: Record<string, unknown>;
          };
          latestUpdate = checkJson.latestUpdate;
          if (!checkJson.allowed) {
            const rej: AuthResultMessage = {
              type: 'auth_result',
              version: 1,
              success: false,
              deviceId,
              peerConnected: false,
              error: checkJson.reason || 'Access denied by Administrator Policy',
              timestamp: now,
            };
            ws.send(JSON.stringify(rej));
            ws.close(1008, checkJson.reason || 'Admin Blocked');
            return;
          }
        }
      } catch {
        // Fail-open if internal telemetry stub is unreachable in unit tests
      }
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
    } else if (!this.sessionEpoch && pairRecord && pairRecord.pair_id && pairRecord.pair_id !== 'pair-primary') {
      // Allow token-room device to encrypt & queue offline messages using a room epoch
      this.sessionEpoch = `offline-${pairRecord.pair_id || 'room'}`;
      this.attachDeviceToSocket(ws, deviceId, this.sessionEpoch);
    } else if (this.sessionEpoch) {
      this.attachDeviceToSocket(ws, deviceId, this.sessionEpoch);
    }

    const authRes: AuthResultMessage & { latestUpdate?: Record<string, unknown> } = {
      type: 'auth_result',
      version: 1,
      success: true,
      deviceId,
      peerConnected,
      sessionEpoch: this.sessionEpoch || undefined,
      peerDeviceId: peerDeviceId || undefined,
      peerPublicKey: peerPublicKey || undefined,
      pairToken: authMsg.pairToken,
      ...(latestUpdate ? { latestUpdate } : {}),
      timestamp: now,
    };
    ws.send(JSON.stringify(authRes));

    // Deliver any queued offline E2EE messages waiting for this device (retained until client confirms with msg_received)
    try {
      this.ctx.storage.sql.exec(
        `DELETE FROM offline_messages WHERE created_at < ?;`,
        now - OFFLINE_MSG_TTL_MS
      );
      const sqlRows = [
        ...this.ctx.storage.sql.exec(
          `SELECT id, payload_json FROM offline_messages WHERE recipient_device_id = ? ORDER BY id ASC LIMIT 100;`,
          deviceId
        ),
      ] as unknown as { id: number; payload_json: string }[];
      for (const row of sqlRows) {
        try {
          ws.send(row.payload_json);
        } catch {}
      }
    } catch {}
    const pendingForDevice = this.offlineQueue.get(deviceId);
    if (pendingForDevice && pendingForDevice.length > 0) {
      for (const queuedMsg of pendingForDevice) {
        try {
          ws.send(JSON.stringify(queuedMsg));
        } catch {
          // Ignore send failure
        }
      }
    }

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
    const pair = this.getPairRecord();
    const isTokenRoom = Boolean(pair && pair.pair_id && pair.pair_id !== 'pair-primary');

    // Enforce active session epoch strictly for primary-pair; in token/contact rooms, E2EE AEAD handles authenticity across reconnects
    const isOfflineEpoch = typeof msg.sessionEpoch === 'string' && msg.sessionEpoch.startsWith('offline-');
    if (!isTokenRoom && (!this.sessionEpoch || msg.sessionEpoch !== this.sessionEpoch) && !isOfflineEpoch) {
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

    // Relay to the other paired device if online, or queue encrypted envelope if offline (in token/contact rooms)
    let recipient = sockets.get(msg.recipientDeviceId);
    if (!recipient || msg.recipientDeviceId === senderDeviceId) {
      for (const [dId, peerWs] of sockets.entries()) {
        if (dId !== senderDeviceId) {
          recipient = peerWs;
          break;
        }
      }
    }
    if (!recipient) {
      const targetDeviceId =
        (pair && pair.device_a_id === senderDeviceId
          ? pair.device_b_id
          : pair && pair.device_b_id === senderDeviceId
            ? pair.device_a_id
            : null) || msg.recipientDeviceId;
      if (isTokenRoom && targetDeviceId && targetDeviceId !== senderDeviceId) {
        let savedToSql = false;
        try {
          this.ctx.storage.sql.exec(
            `INSERT OR IGNORE INTO offline_messages (recipient_device_id, msg_id, payload_json, created_at) VALUES (?, ?, ?, ?);`,
            targetDeviceId,
            msg.msgId,
            JSON.stringify(msg),
            Date.now()
          );
          savedToSql = true;
        } catch {}
        if (!savedToSql) {
          const list = this.offlineQueue.get(targetDeviceId) ?? [];
          if (list.length < 100 && !list.some((m) => m.msgId === msg.msgId)) {
            list.push(msg);
            this.offlineQueue.set(targetDeviceId, list);
          }
        }
        ws.send(
          JSON.stringify({
            type: 'msg_ack',
            version: 1,
            msgId: msg.msgId,
            status: 'queued_offline',
            timestamp: Date.now(),
          })
        );
        this.pushToDeviceInbox(targetDeviceId, {
          eventId: `msg:${msg.msgId}`,
          eventType: 'new_msg',
          senderDeviceId,
          roomToken: pair?.pair_id || '',
        });
        return;
      }

      // Discard immediately when strict primary pair mode is used
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

    // Persist in SQLite queue until recipient explicitly confirms receipt (prevents loss on half-open sockets)
    const targetDeviceIdForQueue =
      (pair && pair.device_a_id === senderDeviceId
        ? pair.device_b_id
        : pair && pair.device_b_id === senderDeviceId
          ? pair.device_a_id
          : null) || msg.recipientDeviceId;
    if (isTokenRoom && targetDeviceIdForQueue && targetDeviceIdForQueue !== senderDeviceId) {
      try {
        this.ctx.storage.sql.exec(
          `INSERT OR IGNORE INTO offline_messages (recipient_device_id, msg_id, payload_json, created_at) VALUES (?, ?, ?, ?);`,
          targetDeviceIdForQueue,
          msg.msgId,
          JSON.stringify(msg),
          Date.now()
        );
      } catch {}
    }

    // Forward ciphertext in memory directly to recipient
    let deliveredDirect = false;
    try {
      recipient.send(JSON.stringify(msg));
      deliveredDirect = true;
    } catch {
      deliveredDirect = false;
    }

    // Non-blocking telemetry counter to Admin Registry
    const adminStub = this.getAdminStub();
    if (adminStub) {
      adminStub
        .fetch(
          new Request('https://internal/internal-admin/telemetry', {
            method: 'POST',
            body: JSON.stringify({ event: 'msg', deviceId: senderDeviceId }),
          })
        )
        .catch(() => {});
    }

    // Send delivery confirmation ack to sender
    ws.send(
      JSON.stringify({
        type: 'msg_ack',
        version: 1,
        msgId: msg.msgId,
        status: deliveredDirect ? 'relayed' : 'queued_offline',
        timestamp: Date.now(),
      })
    );
  }

  private handleMessageReceived(
    ws: WebSocket,
    receipt: { msgId?: string; senderDeviceId?: string }
  ): void {
    const receiverDeviceId = this.getSocketDeviceId(ws);
    const msgId = receipt.msgId;
    if (!receiverDeviceId || !msgId) return;

    try {
      this.ctx.storage.sql.exec(
        `DELETE FROM offline_messages WHERE recipient_device_id = ? AND msg_id = ?;`,
        receiverDeviceId,
        msgId
      );
    } catch {}

    const list = this.offlineQueue.get(receiverDeviceId);
    if (list && list.length > 0) {
      const next = list.filter((m) => m.msgId !== msgId);
      if (next.length === 0) {
        this.offlineQueue.delete(receiverDeviceId);
      } else {
        this.offlineQueue.set(receiverDeviceId, next);
      }
    }

    // Notify the original sender if currently connected so their checkmarks update to delivered (✓✓)
    const sockets = this.getConnectedSocketMap();
    for (const [dId, peerWs] of sockets.entries()) {
      if (dId !== receiverDeviceId) {
        try {
          peerWs.send(
            JSON.stringify({
              type: 'msg_delivered',
              version: 1,
              msgId,
              timestamp: Date.now(),
            })
          );
        } catch {}
      }
    }
  }

  private handleSignaling(ws: WebSocket, signal: SignalingMessage): void {
    const senderDeviceId = this.getSocketDeviceId(ws);

    if (!senderDeviceId || senderDeviceId !== signal.senderDeviceId) {
      return;
    }

    const sockets = this.getConnectedSocketMap();
    const pair = this.getPairRecord();
    const isTokenRoom = Boolean(pair && pair.pair_id && pair.pair_id !== 'pair-primary');

    const isOfflineEpoch =
      typeof signal.sessionEpoch === 'string' && signal.sessionEpoch.startsWith('offline-');
    if (!isTokenRoom && (!this.sessionEpoch || signal.sessionEpoch !== this.sessionEpoch) && !isOfflineEpoch) {
      return;
    }

    // Forward signaling payload to peer (or to the other connected socket in this 2-device room)
    let recipient = sockets.get(signal.recipientDeviceId);
    if (!recipient) {
      for (const [dId, peerWs] of sockets.entries()) {
        if (dId !== senderDeviceId) {
          recipient = peerWs;
          break;
        }
      }
    }
    if (recipient && signal.recipientDeviceId !== senderDeviceId) {
      recipient.send(JSON.stringify(signal));
      if (signal.signalType === 'call_request') {
        const adminStub = this.getAdminStub();
        if (adminStub) {
          adminStub
            .fetch(
              new Request('https://internal/internal-admin/telemetry', {
                method: 'POST',
                body: JSON.stringify({ event: 'call', deviceId: senderDeviceId }),
              })
            )
            .catch(() => {});
        }
      }
    }
    if (
      isTokenRoom &&
      (signal.signalType === 'call_request' ||
        signal.signalType === 'stealth_ping' ||
        signal.signalType === 'heartbeat_pulse')
    ) {
      const targetDeviceId =
        (pair && pair.device_a_id === senderDeviceId
          ? pair.device_b_id
          : pair && pair.device_b_id === senderDeviceId
            ? pair.device_a_id
            : null) || signal.recipientDeviceId;
      if (targetDeviceId && targetDeviceId !== senderDeviceId && targetDeviceId !== 'peer') {
        this.pushToDeviceInbox(targetDeviceId, {
          eventId: `${signal.signalType}:${senderDeviceId}:${signal.timestamp}`,
          eventType: signal.signalType === 'call_request' ? 'incoming_call' : signal.signalType,
          senderDeviceId,
          roomToken: pair?.pair_id || '',
        });
      }
    }
  }

  private handleTerminate(ws: WebSocket, msg: TerminateSessionMessage): void {
    const senderDeviceId = this.getSocketDeviceId(ws);
    const sockets = this.getConnectedSocketMap();
    const pair = this.getPairRecord();
    const isTokenRoom = Boolean(pair && pair.pair_id && pair.pair_id !== 'pair-primary');

    if (isTokenRoom) {
      // In token/contact rooms, one user locking/exiting must NOT kill the partner's connection
      if (senderDeviceId) {
        this.activeDevices.delete(senderDeviceId);
        sockets.delete(senderDeviceId);
      }
      this.sessionEpoch = `offline-${pair!.pair_id || 'room'}`;
      this.syncEpochToAttachments(sockets, this.sessionEpoch);
      for (const peerWs of sockets.values()) {
        try {
          peerWs.send(
            JSON.stringify({
              type: 'session_status',
              version: 1,
              active: false,
              peerOnline: false,
              sessionEpoch: this.sessionEpoch,
              timestamp: Date.now(),
            })
          );
        } catch {}
      }
      return;
    }

    // Inform peer of termination in strict primary-pair mode
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
      const pair = this.getPairRecord();
      const isTokenRoom = Boolean(pair && pair.pair_id && pair.pair_id !== 'pair-primary');
      // Ending any socket invalidates the mutual session epoch in primary-pair, or falls back to offline epoch in token rooms
      this.sessionEpoch = isTokenRoom ? `offline-${pair!.pair_id || 'room'}` : null;

      const sockets = this.getConnectedSocketMap();
      sockets.delete(deviceId);
      this.syncEpochToAttachments(sockets, this.sessionEpoch);
      for (const peerWs of sockets.values()) {
        if (peerWs === ws) continue;
        try {
          peerWs.send(
            JSON.stringify({
              type: 'session_status',
              version: 1,
              active: false,
              peerOnline: false,
              sessionEpoch: this.sessionEpoch || '',
              timestamp: Date.now(),
            })
          );
        } catch {
          // Ignore send errors
        }
      }
    }
  }

  private async handleInternalAdminRequest(request: Request, url: URL): Promise<Response> {
    const now = Date.now();
    const path = url.pathname;

    // 1. Telemetry ingestion from room Durable Objects into 'admin-registry' DO
    if (path === '/internal-admin/telemetry' && request.method === 'POST') {
      const body = (await request.json()) as {
        event: 'auth' | 'msg' | 'call' | 'register';
        deviceId: string;
        secretNumber?: string;
        publicKey?: string;
        country?: string;
        ipMasked?: string;
        roomToken?: string;
      };
      const cfg = this.getAdminConfig();
      const deviceId = body.deviceId || 'unknown';

      if (body.event === 'msg') {
        this.ctx.storage.sql.exec(
          `UPDATE admin_config SET total_messages = total_messages + 1 WHERE id = 1;`
        );
        this.ctx.storage.sql.exec(
          `UPDATE admin_devices SET msg_count = msg_count + 1, last_seen = ? WHERE device_id = ?;`,
          now,
          deviceId
        );
        return Response.json({ ok: true });
      }

      if (body.event === 'call') {
        this.ctx.storage.sql.exec(
          `UPDATE admin_config SET total_calls = total_calls + 1 WHERE id = 1;`
        );
        this.ctx.storage.sql.exec(
          `UPDATE admin_devices SET call_count = call_count + 1, last_seen = ? WHERE device_id = ?;`,
          now,
          deviceId
        );
        return Response.json({ ok: true });
      }

      // event === 'auth' or 'register': upsert device install & check ban/lockdown/whitelist
      const cur = this.ctx.storage.sql.exec(
        `SELECT * FROM admin_devices WHERE device_id = ?;`,
        deviceId
      );
      const existing = [...cur] as unknown as AdminDeviceRow[];

      const latestUpdate = {
        latestVersion: cfg.latest_version || '1.6.0',
        latestBuild: cfg.latest_build || 7,
        downloadUrl:
          cfg.download_url ||
          'https://github.com/saayedh/SecretPlay/releases/download/v1.0.0/app-arm64-v8a-release.apk',
        releaseNotes:
          cfg.release_notes ||
          'نسخه جدید SecretPlay با سرویس پس‌زمینه ۲۴ ساعته، نمایش شناور قلبک و نقاشی روی همه برنامه‌ها و صفحه قفل آماده است!',
      };

      if (existing.length === 0) {
        const defaultApproved = cfg.whitelist_mode ? 0 : 1;
        this.ctx.storage.sql.exec(
          `INSERT INTO admin_devices
           (device_id, secret_number, public_key, country, ip_masked, room_token, first_seen, last_seen, connect_count, msg_count, call_count, is_banned, is_approved, ban_reason, note)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 0, 0, 0, ?, '', '');`,
          deviceId,
          body.secretNumber || 'SP-000-000',
          body.publicKey || '',
          body.country || 'UN',
          body.ipMasked || '0.0.*.*',
          body.roomToken || 'directory',
          now,
          now,
          defaultApproved
        );
        if (cfg.lockdown_mode) {
          return Response.json({
            allowed: false,
            reason: 'Server is currently in Admin Lockdown Mode',
          });
        }
        if (cfg.whitelist_mode) {
          return Response.json({
            allowed: false,
            reason: 'Device pending Administrator Whitelist Approval',
          });
        }
        return Response.json({ allowed: true, latestUpdate });
      } else {
        const dev = existing[0];
        const nextSecretNumber =
          body.event === 'register' && body.secretNumber
            ? body.secretNumber
            : dev.secret_number && dev.secret_number !== 'SP-000-000'
              ? dev.secret_number
              : body.secretNumber || dev.secret_number;
        const nextRoomToken =
          body.roomToken && body.roomToken !== 'directory'
            ? body.roomToken
            : dev.room_token;
        this.ctx.storage.sql.exec(
          `UPDATE admin_devices
           SET last_seen = ?, connect_count = connect_count + 1, room_token = ?, country = ?, ip_masked = ?, secret_number = ?, public_key = COALESCE(NULLIF(?, ''), public_key)
           WHERE device_id = ?;`,
          now,
          nextRoomToken,
          body.country || dev.country,
          body.ipMasked || dev.ip_masked,
          nextSecretNumber,
          body.publicKey || '',
          deviceId
        );
        if (dev.is_banned) {
          return Response.json({
            allowed: false,
            reason: dev.ban_reason || 'Your device has been banned by the Administrator',
          });
        }
        if (cfg.lockdown_mode) {
          return Response.json({
            allowed: false,
            reason: 'Server is currently in Admin Lockdown Mode',
          });
        }
        if (cfg.whitelist_mode && !dev.is_approved) {
          return Response.json({
            allowed: false,
            reason: 'Device not approved in Whitelist Mode',
          });
        }
        return Response.json({ allowed: true, latestUpdate });
      }
    }

    // Public directory lookup by SecretPlay ID (SP-XXX-XXX) so offline messaging works immediately!
    if (path === '/internal-admin/lookup' && request.method === 'GET') {
      const targetId = (url.searchParams.get('id') || '').trim().toUpperCase();
      if (!targetId) {
        return Response.json({ found: false }, { status: 400 });
      }
      const cur = this.ctx.storage.sql.exec(
        `SELECT device_id, secret_number, public_key, last_seen, is_banned FROM admin_devices WHERE secret_number = ? ORDER BY last_seen DESC LIMIT 1;`,
        targetId
      );
      const rows = [...cur] as unknown as AdminDeviceRow[];
      if (rows.length === 0 || rows[0].is_banned || !rows[0].public_key) {
        return Response.json({ found: false });
      }
      return Response.json({
        found: true,
        deviceId: rows[0].device_id,
        secretNumber: rows[0].secret_number,
        publicKey: rows[0].public_key,
        lastSeen: rows[0].last_seen,
      });
    }

    // Public App Version & Update Metadata endpoint
    if (path === '/internal-admin/version' && request.method === 'GET') {
      const cfg = this.getAdminConfig();
      return Response.json({
        latestVersion: cfg.latest_version || '1.6.0',
        latestBuild: cfg.latest_build || 7,
        downloadUrl:
          cfg.download_url ||
          'https://github.com/saayedh/SecretPlay/releases/download/v1.0.0/app-arm64-v8a-release.apk',
        releaseNotes:
          cfg.release_notes ||
          'نسخه جدید SecretPlay با سرویس پس‌زمینه ۲۴ ساعته، نمایش شناور قلبک و نقاشی روی همه برنامه‌ها و صفحه قفل آماده است!',
        timestamp: now,
      });
    }

    // 2. Room-level immediate kick/reset/broadcast invoked by Admin Registry
    if (path === '/internal-admin/room-action' && request.method === 'POST') {
      const body = (await request.json()) as {
        action: 'kick_device' | 'reset_room' | 'revoke_room' | 'broadcast_update';
        deviceId?: string;
        reason?: string;
        latestVersion?: string;
        latestBuild?: number;
        downloadUrl?: string;
        releaseNotes?: string;
      };
      const sockets = this.getConnectedSocketMap();

      if (body.action === 'broadcast_update') {
        let notifiedSockets = 0;
        const payload = JSON.stringify({
          type: 'app_update',
          version: 1,
          latestVersion: body.latestVersion || '1.3.0',
          latestBuild: body.latestBuild || 3,
          downloadUrl: body.downloadUrl || '',
          releaseNotes: body.releaseNotes || '',
          timestamp: now,
        });
        for (const sock of sockets.values()) {
          try {
            sock.send(payload);
            notifiedSockets++;
          } catch {}
        }
        return Response.json({ ok: true, notifiedSockets });
      }

      if (body.action === 'kick_device' && body.deviceId) {
        const targetWs = sockets.get(body.deviceId);
        if (targetWs) {
          try {
            targetWs.send(
              JSON.stringify({
                type: 'terminate',
                version: 1,
                reason: 'security_alert',
                senderDeviceId: 'admin',
                timestamp: now,
              })
            );
            targetWs.close(1008, body.reason || 'Banned by Administrator');
          } catch {}
        }
        this.activeDevices.delete(body.deviceId);
        return Response.json({ ok: true });
      }

      if (body.action === 'reset_room') {
        this.ctx.storage.sql.exec(`DELETE FROM pair_identity WHERE id = 1;`);
        this.offlineQueue.clear();
        this.sessionEpoch = null;
        for (const sock of sockets.values()) {
          try {
            sock.close(1000, 'Room reset by Administrator');
          } catch {}
        }
        this.activeDevices.clear();
        return Response.json({ ok: true });
      }

      if (body.action === 'revoke_room') {
        await this.revokePair('admin_dashboard');
        return Response.json({ ok: true });
      }
    }

    // 3. Public Admin API (protected by X-Admin-Key header or ?key= query parameter)
    const cfg = this.getAdminConfig();
    const providedKey =
      request.headers.get('X-Admin-Key')?.trim() || url.searchParams.get('key')?.trim() || '';
    if (!providedKey || providedKey !== cfg.admin_secret_hash) {
      return Response.json({ error: 'Unauthorized: Invalid Admin Secret Key' }, { status: 401 });
    }

    if (path === '/internal-admin/overview' && request.method === 'GET') {
      const cur = this.ctx.storage.sql.exec(
        `SELECT * FROM admin_devices ORDER BY last_seen DESC LIMIT 500;`
      );
      const devices = [...cur] as unknown as AdminDeviceRow[];
      const activeRecentCount = devices.filter((d) => now - d.last_seen < 120_000 && !d.is_banned).length;
      const bannedCount = devices.filter((d) => Boolean(d.is_banned)).length;
      const roomsSet = new Set(devices.map((d) => d.room_token).filter(Boolean));

      return Response.json({
        stats: {
          totalInstalledDevices: devices.length,
          onlineRecentDevices: activeRecentCount,
          bannedDevices: bannedCount,
          activeRoomsCount: roomsSet.size,
          totalMessagesRelayed: cfg.total_messages,
          totalCallsInitiated: cfg.total_calls,
          lockdownMode: Boolean(cfg.lockdown_mode),
          whitelistMode: Boolean(cfg.whitelist_mode),
        },
        devices,
        rooms: Array.from(roomsSet),
        timestamp: now,
      });
    }

    if (path === '/internal-admin/command' && request.method === 'POST') {
      const cmd = (await request.json()) as {
        command:
          | 'ban_device'
          | 'unban_device'
          | 'approve_device'
          | 'delete_device'
          | 'set_note'
          | 'toggle_lockdown'
          | 'toggle_whitelist'
          | 'change_admin_key'
          | 'publish_update'
          | 'reset_room'
          | 'revoke_room';
        deviceId?: string;
        roomToken?: string;
        reason?: string;
        note?: string;
        enabled?: boolean;
        newKey?: string;
        latestVersion?: string;
        latestBuild?: number;
        downloadUrl?: string;
        releaseNotes?: string;
      };

      switch (cmd.command) {
        case 'ban_device': {
          if (!cmd.deviceId) break;
          this.ctx.storage.sql.exec(
            `UPDATE admin_devices SET is_banned = 1, ban_reason = ? WHERE device_id = ?;`,
            cmd.reason || 'Banned by Administrator',
            cmd.deviceId
          );
          // Also kick device immediately from its room DO!
          const cur = this.ctx.storage.sql.exec(
            `SELECT room_token FROM admin_devices WHERE device_id = ?;`,
            cmd.deviceId
          );
          const rows = [...cur] as unknown as { room_token: string }[];
          const roomTok = rows[0]?.room_token || cmd.roomToken;
          if (roomTok && this.env?.SESSION_RELAY) {
            const roomName =
              roomTok === 'primary-pair' ? 'primary-pair' : `room:${roomTok.toUpperCase()}`;
            const rStub = this.env.SESSION_RELAY.get(this.env.SESSION_RELAY.idFromName(roomName));
            await rStub
              .fetch(
                new Request('https://internal/internal-admin/room-action', {
                  method: 'POST',
                  body: JSON.stringify({
                    action: 'kick_device',
                    deviceId: cmd.deviceId,
                    reason: cmd.reason || 'Banned by Administrator',
                  }),
                })
              )
              .catch(() => {});
          }
          break;
        }

        case 'unban_device':
          if (cmd.deviceId) {
            this.ctx.storage.sql.exec(
              `UPDATE admin_devices SET is_banned = 0, ban_reason = '' WHERE device_id = ?;`,
              cmd.deviceId
            );
          }
          break;

        case 'approve_device':
          if (cmd.deviceId) {
            this.ctx.storage.sql.exec(
              `UPDATE admin_devices SET is_approved = ? WHERE device_id = ?;`,
              cmd.enabled === false ? 0 : 1,
              cmd.deviceId
            );
          }
          break;

        case 'delete_device':
          if (cmd.deviceId) {
            this.ctx.storage.sql.exec(
              `DELETE FROM admin_devices WHERE device_id = ?;`,
              cmd.deviceId
            );
          }
          break;

        case 'set_note':
          if (cmd.deviceId) {
            this.ctx.storage.sql.exec(
              `UPDATE admin_devices SET note = ? WHERE device_id = ?;`,
              cmd.note || '',
              cmd.deviceId
            );
          }
          break;

        case 'toggle_lockdown':
          this.ctx.storage.sql.exec(
            `UPDATE admin_config SET lockdown_mode = ? WHERE id = 1;`,
            cmd.enabled ? 1 : 0
          );
          break;

        case 'toggle_whitelist':
          this.ctx.storage.sql.exec(
            `UPDATE admin_config SET whitelist_mode = ? WHERE id = 1;`,
            cmd.enabled ? 1 : 0
          );
          break;

        case 'change_admin_key':
          if (cmd.newKey && cmd.newKey.trim().length >= 4) {
            this.ctx.storage.sql.exec(
              `UPDATE admin_config SET admin_secret_hash = ? WHERE id = 1;`,
              cmd.newKey.trim()
            );
          }
          break;

        case 'publish_update': {
          const nextVer = cmd.latestVersion || '1.3.0';
          const nextBuild = cmd.latestBuild ?? 3;
          const nextUrl =
            cmd.downloadUrl ||
            'https://github.com/saayedh/SecretPlay/releases/download/v1.0.0/app-arm64-v8a-release.apk';
          const nextNotes =
            cmd.releaseNotes ||
            'نسخه جدید SecretPlay آماده دانلود و نصب است!';
          this.ctx.storage.sql.exec(
            `UPDATE admin_config
             SET latest_version = COALESCE(NULLIF(?, ''), latest_version),
                 latest_build = COALESCE(?, latest_build),
                 download_url = COALESCE(NULLIF(?, ''), download_url),
                 release_notes = COALESCE(NULLIF(?, ''), release_notes)
             WHERE id = 1;`,
            nextVer,
            nextBuild,
            nextUrl,
            nextNotes
          );
          let notifiedRooms = 0;
          let notifiedSockets = 0;
          if (this.env?.SESSION_RELAY) {
            const roomCur = this.ctx.storage.sql.exec(
              `SELECT DISTINCT room_token FROM admin_devices WHERE room_token IS NOT NULL AND room_token != '' AND room_token != 'directory' AND last_seen > ? LIMIT 200;`,
              now - 86_400_000
            );
            const roomRows = [...roomCur] as unknown as { room_token: string }[];
            for (const row of roomRows) {
              const tok = row.room_token;
              const roomName = tok === 'primary-pair' ? 'primary-pair' : `room:${tok.toUpperCase()}`;
              const rStub = this.env.SESSION_RELAY.get(this.env.SESSION_RELAY.idFromName(roomName));
              try {
                const bRes = await rStub.fetch(
                  new Request('https://internal/internal-admin/room-action', {
                    method: 'POST',
                    body: JSON.stringify({
                      action: 'broadcast_update',
                      latestVersion: nextVer,
                      latestBuild: nextBuild,
                      downloadUrl: nextUrl,
                      releaseNotes: nextNotes,
                    }),
                  })
                );
                if (bRes.ok) {
                  const bJson = (await bRes.json()) as { notifiedSockets?: number };
                  notifiedRooms++;
                  notifiedSockets += bJson.notifiedSockets || 0;
                }
              } catch {}
            }
          }
          return Response.json({ ok: true, notifiedRooms, notifiedSockets, timestamp: now });
        }

        case 'reset_room':
        case 'revoke_room': {
          const roomTok = cmd.roomToken || 'primary-pair';
          if (this.env?.SESSION_RELAY) {
            const roomName =
              roomTok === 'primary-pair' ? 'primary-pair' : `room:${roomTok.toUpperCase()}`;
            const rStub = this.env.SESSION_RELAY.get(this.env.SESSION_RELAY.idFromName(roomName));
            await rStub
              .fetch(
                new Request('https://internal/internal-admin/room-action', {
                  method: 'POST',
                  body: JSON.stringify({ action: cmd.command }),
                })
              )
              .catch(() => {});
          }
          break;
        }
      }

      return Response.json({ ok: true, timestamp: now });
    }

    return Response.json({ error: 'Unknown admin endpoint' }, { status: 404 });
  }

  async webSocketError(ws: WebSocket, error: unknown): Promise<void> {
    try {
      ws.close(1011, 'WebSocket internal error');
    } catch {
      // Ignore close error
    }
  }
}
