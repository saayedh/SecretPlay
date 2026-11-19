const test = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');
const path = require('node:path');
const fs = require('node:fs');
const esbuild = require('esbuild');
const {
  generateIdentityBundle,
  signAuthChallenge,
  encryptEnvelope,
  decryptEnvelope,
  SIGNAL_KEY_HKDF_INFO,
} = require('../../crypto_core/dist/index');

class MockSqlStorage {
  constructor() {
    this.rows = new Map();
  }

  exec(sql, ...params) {
    const normalized = sql.trim().replace(/\s+/g, ' ').toUpperCase();
    if (normalized.startsWith('CREATE TABLE')) {
      return [];
    }
    if (normalized.startsWith('SELECT * FROM PAIR_IDENTITY')) {
      const row = this.rows.get(1);
      return row ? [{ ...row }] : [];
    }
    if (normalized.startsWith('INSERT OR REPLACE INTO PAIR_IDENTITY')) {
      if (normalized.includes('NULL, NULL, 0, 0')) {
        const [pair_id, device_a_id, device_a_pubkey, updated_at] = params;
        this.rows.set(1, {
          id: 1,
          pair_id,
          device_a_id,
          device_a_pubkey,
          device_b_id: null,
          device_b_pubkey: null,
          is_paired: 0,
          is_revoked: 0,
          updated_at,
        });
        return [];
      }
      const [pair_id, device_a_id, device_a_pubkey, device_b_id, device_b_pubkey, updated_at] = params;
      this.rows.set(1, {
        id: 1,
        pair_id,
        device_a_id,
        device_a_pubkey,
        device_b_id,
        device_b_pubkey,
        is_paired: 1,
        is_revoked: 0,
        updated_at,
      });
      return [];
    }
    if (normalized.startsWith('UPDATE PAIR_IDENTITY SET DEVICE_A_ID')) {
      const row = this.rows.get(1);
      if (row) {
        row.device_a_id = params[0];
        row.device_a_pubkey = params[1];
        row.updated_at = params[2];
      }
      return [];
    }
    if (normalized.startsWith('UPDATE PAIR_IDENTITY SET DEVICE_B_ID')) {
      const row = this.rows.get(1);
      if (row) {
        row.device_b_id = params[0];
        row.device_b_pubkey = params[1];
        row.is_paired = 1;
        row.updated_at = params[2];
      }
      return [];
    }
    if (normalized.startsWith('UPDATE PAIR_IDENTITY SET IS_PAIRED = 0, IS_REVOKED = 1')) {
      const row = this.rows.get(1);
      if (row) {
        row.is_paired = 0;
        row.is_revoked = 1;
        row.updated_at = params[0];
      }
      return [];
    }
    throw new Error(`Unsupported mock SQL query: ${sql}`);
  }
}

class MockWebSocket {
  constructor(name) {
    this.name = name;
    this.sent = [];
    this.closed = null;
    this.attachment = null;
    this.accepted = false;
  }

  send(data) {
    if (this.closed) {
      throw new Error('WebSocket is closed');
    }
    this.sent.push(JSON.parse(String(data)));
  }

  close(code = 1000, reason = '') {
    this.closed = { code, reason };
  }

  serializeAttachment(val) {
    this.attachment = val ? JSON.parse(JSON.stringify(val)) : null;
  }

  deserializeAttachment() {
    return this.attachment ? JSON.parse(JSON.stringify(this.attachment)) : null;
  }

  drain() {
    const out = this.sent.splice(0, this.sent.length);
    return out;
  }
}

class MockDurableObjectState {
  constructor(sqlStorage) {
    this.storage = { sql: sqlStorage };
    this.sockets = [];
  }

  acceptWebSocket(ws) {
    ws.accepted = true;
    this.sockets.push(ws);
  }

  getWebSockets() {
    return this.sockets.filter((s) => !s.closed);
  }

  getTags() {
    return [];
  }
}

function loadCloudflareBundle() {
  const tmpDir = path.join(__dirname, '.tmp_build');
  fs.mkdirSync(tmpDir, { recursive: true });
  const shimPath = path.join(tmpDir, 'cf-workers-shim.js');
  fs.writeFileSync(
    shimPath,
    `class DurableObject { constructor(ctx, env) { this.ctx = ctx; this.env = env; } }\nmodule.exports = { DurableObject };\n`,
    'utf8'
  );

  const outFile = path.join(tmpDir, 'worker.cjs');
  esbuild.buildSync({
    entryPoints: [path.resolve(__dirname, '../src/index.ts')],
    bundle: true,
    platform: 'node',
    format: 'cjs',
    outfile: outFile,
    alias: {
      'cloudflare:workers': shimPath,
    },
  });

  // Ensure fresh load
  delete require.cache[require.resolve(outFile)];
  return require(outFile);
}

test('SecretPlay Cloudflare Worker & Durable Object Relay Test Suite', async (t) => {
  const workerBundle = loadCloudflareBundle();
  const worker = workerBundle.default;
  const { SecretPlaySessionRelay } = workerBundle;

  let sqlStorage;
  let state;
  let relay;

  function createEnv(extra = {}) {
    return {
      SESSION_RELAY: {
        idFromName: () => 'primary-pair-id',
        get: () => relay,
      },
      ...extra,
    };
  }

  t.beforeEach(() => {
    sqlStorage = new MockSqlStorage();
    state = new MockDurableObjectState(sqlStorage);
    relay = new SecretPlaySessionRelay(state, createEnv());
  });

  t.after(() => {
    const tmpDir = path.join(__dirname, '.tmp_build');
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  await t.test('1. Worker root /, /health, and /turn (free-tier STUN default vs enabled TURN)', async () => {
    const envDefault = createEnv();
    const rootRes = await worker.fetch(new Request('https://relay.example.com/'), envDefault, {});
    assert.strictEqual(rootRes.status, 200);
    const rootBody = await rootRes.json();
    assert.strictEqual(rootBody.freeTierMode, true);
    assert.strictEqual(rootBody.zeroStorage, true);
    assert.strictEqual(rootBody.turnEnabled, false);

    const healthRes = await worker.fetch(new Request('https://relay.example.com/health'), envDefault, {});
    assert.strictEqual(healthRes.status, 200);
    const healthBody = await healthRes.json();
    assert.strictEqual(healthBody.status, 'healthy');
    assert.strictEqual(healthBody.isPaired, false);

    const turnRes = await worker.fetch(new Request('https://relay.example.com/turn'), envDefault, {});
    assert.strictEqual(turnRes.status, 200);
    const turnBody = await turnRes.json();
    assert.strictEqual(turnBody.turnEnabled, false);
    assert.ok(Array.isArray(turnBody.iceServers));
    assert.strictEqual(turnBody.iceServers[0].urls, 'stun:stun.cloudflare.com:3478');

    // Mock TURN enabled path
    const originalFetch = global.fetch;
    global.fetch = async (url) => {
      assert.match(String(url), /\/credentials\/generate-ice-servers$/);
      return new Response(JSON.stringify({ iceServers: [{ urls: 'turn:turn.cloudflare.com:3478', username: 'u', credential: 'c' }] }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    };
    try {
      const envTurn = createEnv({
        ENABLE_CLOUDFLARE_TURN: 'true',
        CF_TURN_KEY_ID: 'turn-key-1',
        CF_TURN_API_TOKEN: 'turn-secret-token',
      });
      const turnEnabledRes = await worker.fetch(new Request('https://relay.example.com/turn'), envTurn, {});
      assert.strictEqual(turnEnabledRes.status, 200);
      const turnEnabledBody = await turnEnabledRes.json();
      assert.strictEqual(turnEnabledBody.turnEnabled, true);
      assert.strictEqual(turnEnabledBody.iceServers[0].urls, 'turn:turn.cloudflare.com:3478');
    } finally {
      global.fetch = originalFetch;
    }
  });

  await t.test('2-10. Full pairing, 3rd device rejection, Ed25519 auth, E2EE relay, signaling, zero offline storage, lock, and revocation', async () => {
    const alice = generateIdentityBundle();
    const bob = generateIdentityBundle();
    const eve = generateIdentityBundle();
    const inviteCode = crypto.randomBytes(16).toString('hex');

    const wsA = new MockWebSocket('alice');
    const wsB = new MockWebSocket('bob');
    state.acceptWebSocket(wsA);
    state.acceptWebSocket(wsB);

    // 2. Pairing init & claim
    await relay.webSocketMessage(
      wsA,
      JSON.stringify({
        type: 'pairing_init',
        version: 1,
        invitationCode: inviteCode,
        deviceAId: 'dev-alice',
        deviceAPublicKey: alice.publicKeyBase64,
        timestamp: Date.now(),
      })
    );
    assert.strictEqual(wsA.drain()[0].success, true);

    await relay.webSocketMessage(
      wsB,
      JSON.stringify({
        type: 'pairing_claim',
        version: 1,
        invitationCode: inviteCode,
        deviceBId: 'dev-bob',
        deviceBPublicKey: bob.publicKeyBase64,
        timestamp: Date.now(),
      })
    );
    const confirmB = wsB.drain()[0];
    const confirmA = wsA.drain()[0];
    assert.strictEqual(confirmB.success, true);
    assert.strictEqual(confirmB.peerDeviceId, 'dev-alice');
    assert.strictEqual(confirmB.peerPublicKey, alice.publicKeyBase64);
    assert.strictEqual(confirmA.success, true);
    assert.strictEqual(confirmA.peerDeviceId, 'dev-bob');
    assert.strictEqual(confirmA.peerPublicKey, bob.publicKeyBase64);

    // 3. Rejection of re-pairing while paired
    const wsEve = new MockWebSocket('eve');
    state.acceptWebSocket(wsEve);
    await relay.webSocketMessage(
      wsEve,
      JSON.stringify({
        type: 'pairing_init',
        version: 1,
        invitationCode: 'second-invite',
        deviceAId: 'dev-eve',
        deviceAPublicKey: eve.publicKeyBase64,
        timestamp: Date.now(),
      })
    );
    const repairReject = wsEve.drain()[0];
    assert.strictEqual(repairReject.success, false);
    assert.match(repairReject.error, /already established/i);

    // 4. Rejection of 3rd unauthorized device on auth
    const eveNonce = crypto.randomBytes(12).toString('hex');
    const eveNow = Date.now();
    await relay.webSocketMessage(
      wsEve,
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'dev-eve',
        nonce: eveNonce,
        signature: signAuthChallenge(eve, 'dev-eve', eveNonce, eveNow),
        timestamp: eveNow,
      })
    );
    const eveAuthRes = wsEve.drain()[0];
    assert.strictEqual(eveAuthRes.success, false);
    assert.strictEqual(wsEve.closed.code, 1008);

    // Simulate closing initial sockets & reconnecting with Ed25519 challenge-response
    await relay.webSocketClose(wsA, 1000, 'reconnect');
    await relay.webSocketClose(wsB, 1000, 'reconnect');
    wsA.close(1000, 'reconnect');
    wsB.close(1000, 'reconnect');

    const wsA2 = new MockWebSocket('alice-2');
    const wsB2 = new MockWebSocket('bob-2');
    state.acceptWebSocket(wsA2);
    state.acceptWebSocket(wsB2);

    // Invalid Ed25519 signature rejected even for authorized deviceId
    const badNonce = crypto.randomBytes(12).toString('hex');
    const badNow = Date.now();
    const wsImposter = new MockWebSocket('imposter');
    state.acceptWebSocket(wsImposter);
    await relay.webSocketMessage(
      wsImposter,
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'dev-alice',
        nonce: badNonce,
        signature: signAuthChallenge(eve, 'dev-alice', badNonce, badNow),
        timestamp: badNow,
      })
    );
    assert.strictEqual(wsImposter.drain()[0].success, false);
    assert.strictEqual(wsImposter.closed.code, 1008);

    // Valid Ed25519 auth for Alice & Bob
    const nonceA = crypto.randomBytes(12).toString('hex');
    const nowA = Date.now();
    await relay.webSocketMessage(
      wsA2,
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'dev-alice',
        nonce: nonceA,
        signature: signAuthChallenge(alice, 'dev-alice', nonceA, nowA),
        timestamp: nowA,
      })
    );
    assert.strictEqual(wsA2.drain()[0].success, true);

    const nonceB = crypto.randomBytes(12).toString('hex');
    const nowB = Date.now();
    await relay.webSocketMessage(
      wsB2,
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'dev-bob',
        nonce: nonceB,
        signature: signAuthChallenge(bob, 'dev-bob', nonceB, nowB),
        timestamp: nowB,
      })
    );
    const authResB = wsB2.drain()[0];
    const statusA = wsA2.drain()[0];
    assert.strictEqual(authResB.success, true);
    assert.strictEqual(authResB.peerConnected, true);
    assert.ok(authResB.sessionEpoch);
    assert.strictEqual(statusA.type, 'session_status');
    assert.strictEqual(statusA.peerOnline, true);

    const epoch = authResB.sessionEpoch;

    // 5. WebSocket Hibernation simulation: instantiate a fresh SecretPlaySessionRelay sharing SQLite & sockets!
    const hibernatedRelay = new SecretPlaySessionRelay(state, createEnv());

    // 6. Encrypted chat message relay after hibernation wake-up
    const env = encryptEnvelope({
      plaintext: 'Secret cloud E2EE message after hibernation!',
      recipientPublicKeyBase64: bob.publicKeyBase64,
      senderIdentity: alice,
      sessionEpoch: epoch,
      seq: 1,
    });
    await hibernatedRelay.webSocketMessage(
      wsA2,
      JSON.stringify({
        type: 'msg',
        version: 1,
        msgId: 'msg-cf-1',
        senderDeviceId: 'dev-alice',
        recipientDeviceId: 'dev-bob',
        sessionEpoch: epoch,
        ...env,
        timestamp: Date.now(),
      })
    );
    const bobGotMsg = wsB2.drain()[0];
    const aliceGotAck = wsA2.drain()[0];
    assert.strictEqual(bobGotMsg.type, 'msg');
    assert.strictEqual(aliceGotAck.status, 'relayed');

    const decrypted = decryptEnvelope({
      envelope: bobGotMsg,
      recipientIdentity: bob,
      senderPublicKeyBase64: alice.publicKeyBase64,
      sessionEpoch: epoch,
      lastSeq: 0,
    });
    assert.strictEqual(decrypted, 'Secret cloud E2EE message after hibernation!');

    // 7. Encrypted WebRTC signaling relay
    const sigEnv = encryptEnvelope({
      plaintext: JSON.stringify({ type: 'offer', sdp: 'v=0...' }),
      recipientPublicKeyBase64: alice.publicKeyBase64,
      senderIdentity: bob,
      sessionEpoch: epoch,
      seq: 1,
      hkdfInfo: SIGNAL_KEY_HKDF_INFO,
    });
    await hibernatedRelay.webSocketMessage(
      wsB2,
      JSON.stringify({
        type: 'signal',
        version: 1,
        signalType: 'offer',
        senderDeviceId: 'dev-bob',
        recipientDeviceId: 'dev-alice',
        sessionEpoch: epoch,
        encryptedPayload: sigEnv.ciphertext,
        iv: sigEnv.iv,
        authTag: sigEnv.authTag,
        ephemeralPubKey: sigEnv.ephemeralPubKey,
        seq: sigEnv.seq,
        signature: sigEnv.signature,
        timestamp: Date.now(),
      })
    );
    const aliceGotSig = wsA2.drain()[0];
    assert.strictEqual(aliceGotSig.type, 'signal');
    assert.strictEqual(aliceGotSig.signalType, 'offer');

    // 8. Session termination on lock/backgrounding
    await hibernatedRelay.webSocketMessage(
      wsA2,
      JSON.stringify({
        type: 'terminate',
        version: 1,
        reason: 'app_backgrounded',
        senderDeviceId: 'dev-alice',
        timestamp: Date.now(),
      })
    );
    const bobTerm = wsB2.drain()[0];
    assert.strictEqual(bobTerm.type, 'terminate');
    assert.strictEqual(bobTerm.reason, 'app_backgrounded');

    // 9. Zero offline storage check when peer disconnects
    await hibernatedRelay.webSocketClose(wsB2, 1000, 'offline');
    wsB2.close(1000, 'offline');
    const offlineNotice = wsA2.drain()[0];
    assert.strictEqual(offlineNotice.type, 'session_status');
    assert.strictEqual(offlineNotice.peerOnline, false);

    await hibernatedRelay.webSocketMessage(
      wsA2,
      JSON.stringify({
        type: 'msg',
        version: 1,
        msgId: 'msg-offline-drop',
        senderDeviceId: 'dev-alice',
        recipientDeviceId: 'dev-bob',
        sessionEpoch: epoch,
        ...env,
        timestamp: Date.now(),
      })
    );
    const dropRes = wsA2.drain()[0];
    // Session epoch was cleared when Bob closed, so server terminates/rejects stale session immediately
    assert.ok(dropRes.type === 'terminate' || dropRes.status === 'dropped_peer_offline');

    // 10. Explicit device revocation
    const revNonce = crypto.randomBytes(12).toString('hex');
    const revNow = Date.now();
    await hibernatedRelay.webSocketMessage(
      wsA2,
      JSON.stringify({
        type: 'revoke',
        version: 1,
        senderDeviceId: 'dev-alice',
        nonce: revNonce,
        signature: signAuthChallenge(alice, 'dev-alice', revNonce, revNow),
        timestamp: revNow,
      })
    );
    const revConfirm = wsA2.drain()[0];
    assert.strictEqual(revConfirm.type, 'revoke_confirm');
    assert.strictEqual(revConfirm.success, true);

    // Re-auth after revocation must fail
    const wsA3 = new MockWebSocket('alice-after-revoke');
    state.acceptWebSocket(wsA3);
    const n3 = crypto.randomBytes(12).toString('hex');
    const t3 = Date.now();
    await hibernatedRelay.webSocketMessage(
      wsA3,
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'dev-alice',
        nonce: n3,
        signature: signAuthChallenge(alice, 'dev-alice', n3, t3),
        timestamp: t3,
      })
    );
    const afterRevRes = wsA3.drain()[0];
    assert.strictEqual(afterRevRes.success, false);
    assert.match(afterRevRes.error, /revoked/i);
  });

  await t.test('11. Streamlined Shared Pair Token auto-pairing (TOFU) & 3rd device rejection', async () => {
    const alice = generateIdentityBundle();
    const bob = generateIdentityBundle();
    const eve = generateIdentityBundle();
    const sharedToken = 'SP-7492-K9';

    const wsA = new MockWebSocket('token-alice');
    const wsB = new MockWebSocket('token-bob');
    const wsEve = new MockWebSocket('token-eve');
    state.acceptWebSocket(wsA);
    state.acceptWebSocket(wsB);
    state.acceptWebSocket(wsEve);

    // Alice joins token room first -> automatically claims Slot A
    const nA = crypto.randomBytes(12).toString('hex');
    const tA = Date.now();
    await relay.webSocketMessage(
      wsA,
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'dev-alice',
        pairToken: sharedToken,
        publicKey: alice.publicKeyBase64,
        nonce: nA,
        signature: signAuthChallenge(alice, 'dev-alice', nA, tA),
        timestamp: tA,
      })
    );
    const resA = wsA.drain()[0];
    assert.strictEqual(resA.success, true);
    assert.strictEqual(resA.peerConnected, false);

    // Bob joins with same token -> claims Slot B, both receive each other's public keys & sessionEpoch!
    const nB = crypto.randomBytes(12).toString('hex');
    const tB = Date.now();
    await relay.webSocketMessage(
      wsB,
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'dev-bob',
        pairToken: sharedToken,
        publicKey: bob.publicKeyBase64,
        nonce: nB,
        signature: signAuthChallenge(bob, 'dev-bob', nB, tB),
        timestamp: tB,
      })
    );
    const resB = wsB.drain()[0];
    const statusForA = wsA.drain()[0];
    assert.strictEqual(resB.success, true);
    assert.strictEqual(resB.peerConnected, true);
    assert.strictEqual(resB.peerDeviceId, 'dev-alice');
    assert.strictEqual(resB.peerPublicKey, alice.publicKeyBase64);
    assert.strictEqual(statusForA.type, 'session_status');
    assert.strictEqual(statusForA.peerOnline, true);
    assert.strictEqual(statusForA.peerDeviceId, 'dev-bob');
    assert.strictEqual(statusForA.peerPublicKey, bob.publicKeyBase64);

    // Eve (3rd device) tries to join the same token room -> rejected with 1008!
    const nE = crypto.randomBytes(12).toString('hex');
    const tE = Date.now();
    await relay.webSocketMessage(
      wsEve,
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'dev-eve',
        pairToken: sharedToken,
        publicKey: eve.publicKeyBase64,
        nonce: nE,
        signature: signAuthChallenge(eve, 'dev-eve', nE, tE),
        timestamp: tE,
      })
    );
    const resEve = wsEve.drain()[0];
    assert.strictEqual(resEve.success, false);
    assert.strictEqual(wsEve.closed.code, 1008);
  });
});
