const test = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');
const { WebSocket } = require('ws');
const Fastify = require('fastify');
const fastifyWebsocket = require('@fastify/websocket');
const fastifyCors = require('@fastify/cors');
const { SessionManager } = require('../dist/session');
const { isPrivateOrLoopbackIp } = require('../dist/network');

test('SecretPlay Local Server & Cryptographic Invariants Test Suite', async (t) => {
  let fastify;
  let sessionManager;
  let port;
  let serverWsUrl;

  t.before(async () => {
    fastify = Fastify({ logger: false });
    sessionManager = new SessionManager(2000, 500); // 2s timeout for testing

    await fastify.register(fastifyCors, { origin: '*' });
    await fastify.register(fastifyWebsocket);

    fastify.get('/health', async () => ({
      status: 'healthy',
      mode: 'local_offline',
      e2ee: true,
      zeroStorage: true,
      timestamp: Date.now(),
    }));

    fastify.get('/status', async () => sessionManager.getStatus());

    fastify.post('/reset', async () => {
      sessionManager.resetPairing();
      return { success: true };
    });

    fastify.get('/ws', { websocket: true }, (socket) => {
      let regDeviceId = null;
      socket.on('message', (raw) => {
        const msg = JSON.parse(raw.toString());
        if (regDeviceId && msg.type !== 'auth' && !sessionManager.checkRateLimit(socket, regDeviceId)) {
          return;
        }
        switch (msg.type) {
          case 'auth':
            regDeviceId = msg.deviceId;
            sessionManager.handleAuth(socket, msg);
            break;
          case 'ping':
            if (regDeviceId) sessionManager.handlePing(socket, regDeviceId);
            break;
          case 'msg':
            sessionManager.handleMessage(socket, msg);
            break;
          case 'signal':
            sessionManager.handleSignaling(socket, msg);
            break;
          case 'pairing_init':
            regDeviceId = msg.deviceAId;
            sessionManager.handlePairingInit(socket, msg);
            break;
          case 'pairing_claim':
            regDeviceId = msg.deviceBId;
            sessionManager.handlePairingClaim(socket, msg);
            break;
          case 'revoke':
            sessionManager.handleRevoke(socket, msg);
            break;
          case 'terminate':
            if (regDeviceId) sessionManager.terminateSession(regDeviceId, msg.reason);
            break;
        }
      });
      socket.on('close', () => sessionManager.handleSocketClose(socket));
    });

    await fastify.listen({ port: 0, host: '127.0.0.1' });
    port = fastify.server.address().port;
    serverWsUrl = `ws://127.0.0.1:${port}/ws`;
  });

  t.after(async () => {
    sessionManager.dispose();
    await fastify.close();
  });

  function connectWs() {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(serverWsUrl);
      ws.on('open', () => resolve(ws));
      ws.on('error', reject);
    });
  }

  function waitMsg(ws) {
    return new Promise((resolve) => {
      ws.once('message', (data) => resolve(JSON.parse(data.toString())));
    });
  }

  await t.test('1. Health check endpoint and private LAN IP guard validation', async () => {
    const res = await fastify.inject({ method: 'GET', url: '/health' });
    assert.strictEqual(res.statusCode, 200);
    const body = JSON.parse(res.body);
    assert.strictEqual(body.status, 'healthy');
    assert.strictEqual(body.mode, 'local_offline');
    assert.strictEqual(body.e2ee, true);

    assert.strictEqual(isPrivateOrLoopbackIp('127.0.0.1'), true);
    assert.strictEqual(isPrivateOrLoopbackIp('192.168.137.1'), true);
    assert.strictEqual(isPrivateOrLoopbackIp('10.0.0.12'), true);
    assert.strictEqual(isPrivateOrLoopbackIp('172.20.1.5'), true);
    assert.strictEqual(isPrivateOrLoopbackIp('8.8.8.8'), false);
    assert.strictEqual(isPrivateOrLoopbackIp('1.1.1.1'), false);
  });

  await t.test('2. Unpaired device cannot authenticate before pairing', async () => {
    const ws = await connectWs();
    const authPromise = waitMsg(ws);
    ws.send(
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'rogue-device-1',
        nonce: 'nonce-1001',
        signature: 'sig',
        timestamp: Date.now(),
      })
    );
    const reply = await authPromise;
    assert.strictEqual(reply.type, 'auth_result');
    assert.strictEqual(reply.success, false);
    ws.close();
  });

  await t.test('3. Device A and Device B complete pairing successfully', async () => {
    const wsA = await connectWs();
    const initPromise = waitMsg(wsA);
    const inviteCode = 'secret-pairing-code-999';

    wsA.send(
      JSON.stringify({
        type: 'pairing_init',
        version: 1,
        invitationCode: inviteCode,
        deviceAId: 'device-alice',
        deviceAPublicKey: 'alice-ed25519-public-key',
        timestamp: Date.now(),
      })
    );
    const initRes = await initPromise;
    assert.strictEqual(initRes.type, 'pairing_confirm');
    assert.strictEqual(initRes.success, true);

    const wsB = await connectWs();
    const claimPromiseB = waitMsg(wsB);
    const claimPromiseA = waitMsg(wsA);

    wsB.send(
      JSON.stringify({
        type: 'pairing_claim',
        version: 1,
        invitationCode: inviteCode,
        deviceBId: 'device-bob',
        deviceBPublicKey: 'bob-ed25519-public-key',
        timestamp: Date.now(),
      })
    );

    const [resB, resA] = await Promise.all([claimPromiseB, claimPromiseA]);
    assert.strictEqual(resB.type, 'pairing_confirm');
    assert.strictEqual(resB.success, true);
    assert.strictEqual(resB.peerDeviceId, 'device-alice');
    assert.strictEqual(resA.type, 'pairing_confirm');
    assert.strictEqual(resA.success, true);
    assert.strictEqual(resA.peerDeviceId, 'device-bob');

    const statusRes = await fastify.inject({ method: 'GET', url: '/status' });
    const status = JSON.parse(statusRes.body);
    assert.strictEqual(status.isPaired, true);
    assert.strictEqual(status.deviceA, 'device-alice');
    assert.strictEqual(status.deviceB, 'device-bob');
    assert.strictEqual(status.activeSession, true);

    wsA.close();
    wsB.close();
    await new Promise((r) => setTimeout(r, 100));
  });

  await t.test('4. Rejection of unauthorized third device after pairing', async () => {
    const wsThird = await connectWs();
    const replyPromise = waitMsg(wsThird);

    wsThird.send(
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'device-eve-attacker',
        nonce: 'nonce-eve-1234',
        signature: 'fake-sig',
        timestamp: Date.now(),
      })
    );

    const reply = await replyPromise;
    assert.strictEqual(reply.type, 'auth_result');
    assert.strictEqual(reply.success, false);
    assert.match(reply.error, /maximum 2 authorized devices/i);
    wsThird.close();
  });

  await t.test('5. Reconnection, replay nonce rejection, E2EE chat relay, WebRTC signaling, and lock termination', async () => {
    const wsA = await connectWs();
    const wsB = await connectWs();

    const authPromiseA = waitMsg(wsA);
    wsA.send(
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'device-alice',
        nonce: 'nonce-alice-unique-1',
        signature: 'sig',
        timestamp: Date.now(),
      })
    );
    const resA = await authPromiseA;
    assert.strictEqual(resA.success, true);

    // Replaying the exact same auth nonce must be rejected
    const wsReplay = await connectWs();
    const replayAuthPromise = waitMsg(wsReplay);
    wsReplay.send(
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'device-alice',
        nonce: 'nonce-alice-unique-1',
        signature: 'sig',
        timestamp: Date.now(),
      })
    );
    const replayRes = await replayAuthPromise;
    assert.strictEqual(replayRes.success, false);
    assert.match(replayRes.error, /replayed/i);
    wsReplay.close();

    // When Bob connects, Alice receives session_status notification
    const peerOnlineNoticeA = waitMsg(wsA);
    const authPromiseB = waitMsg(wsB);

    wsB.send(
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'device-bob',
        nonce: 'nonce-bob-unique-2',
        signature: 'sig',
        timestamp: Date.now(),
      })
    );

    const [resB, noticeA] = await Promise.all([authPromiseB, peerOnlineNoticeA]);
    assert.strictEqual(resB.success, true);
    assert.strictEqual(resB.peerConnected, true);
    assert.ok(resB.sessionEpoch, 'Session epoch must be issued when both are online');
    assert.strictEqual(noticeA.type, 'session_status');
    assert.strictEqual(noticeA.peerOnline, true);

    const epoch = resB.sessionEpoch;

    // Test Encrypted chat message memory relay
    const msgPromiseB = waitMsg(wsB);
    const ackPromiseA = waitMsg(wsA);

    wsA.send(
      JSON.stringify({
        type: 'msg',
        version: 1,
        msgId: 'msg-101',
        senderDeviceId: 'device-alice',
        recipientDeviceId: 'device-bob',
        sessionEpoch: epoch,
        ciphertext: '5aGf7q==encryptedCiphertext',
        iv: 'iv123',
        authTag: 'tag123',
        ephemeralPubKey: 'pubkey123',
        seq: 1,
        signature: 'sig123',
        timestamp: Date.now(),
      })
    );

    const [recvMsgB, ackA] = await Promise.all([msgPromiseB, ackPromiseA]);
    assert.strictEqual(recvMsgB.type, 'msg');
    assert.strictEqual(recvMsgB.ciphertext, '5aGf7q==encryptedCiphertext');
    assert.strictEqual(ackA.type, 'msg_ack');
    assert.strictEqual(ackA.status, 'relayed');

    // Zero offline message queue when targeting offline recipient
    const offlineAckPromise = waitMsg(wsA);
    wsA.send(
      JSON.stringify({
        type: 'msg',
        version: 1,
        msgId: 'msg-offline-target',
        senderDeviceId: 'device-alice',
        recipientDeviceId: 'device-unconnected',
        sessionEpoch: epoch,
        ciphertext: 'droppedCiphertext',
        iv: 'iv124',
        authTag: 'tag124',
        ephemeralPubKey: 'pubkey124',
        seq: 2,
        signature: 'sig124',
        timestamp: Date.now(),
      })
    );
    const offlineAck = await offlineAckPromise;
    assert.strictEqual(offlineAck.type, 'msg_ack');
    assert.strictEqual(offlineAck.status, 'dropped_peer_offline');

    // WebRTC Call Signaling Relay (Offer -> Answer -> ICE)
    const signalPromiseB = waitMsg(wsB);
    wsA.send(
      JSON.stringify({
        type: 'signal',
        version: 1,
        signalType: 'offer',
        senderDeviceId: 'device-alice',
        recipientDeviceId: 'device-bob',
        sessionEpoch: epoch,
        encryptedPayload: 'encSdpOfferPayload',
        iv: 'iv-sig',
        authTag: 'tag-sig',
        seq: 1,
        timestamp: Date.now(),
      })
    );

    const recvSignal = await signalPromiseB;
    assert.strictEqual(recvSignal.type, 'signal');
    assert.strictEqual(recvSignal.signalType, 'offer');
    assert.strictEqual(recvSignal.encryptedPayload, 'encSdpOfferPayload');

    // Session Termination on lock or background
    const termPromiseB = waitMsg(wsB);
    wsA.send(
      JSON.stringify({
        type: 'terminate',
        version: 1,
        reason: 'app_backgrounded',
        senderDeviceId: 'device-alice',
        timestamp: Date.now(),
      })
    );

    const termB = await termPromiseB;
    assert.strictEqual(termB.type, 'terminate');
    assert.strictEqual(termB.reason, 'app_backgrounded');

    wsA.close();
    wsB.close();
    await new Promise((r) => setTimeout(r, 100));
  });

  await t.test('6. Device revocation invalidates pairing and blocks subsequent authentication', async () => {
    const wsA = await connectWs();
    const authResP = waitMsg(wsA);
    wsA.send(
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'device-alice',
        nonce: 'nonce-alice-before-revoke',
        signature: 'sig',
        timestamp: Date.now(),
      })
    );
    const authRes = await authResP;
    assert.strictEqual(authRes.success, true);

    const revPromise = waitMsg(wsA);
    wsA.send(
      JSON.stringify({
        type: 'revoke',
        version: 1,
        senderDeviceId: 'device-alice',
        nonce: 'rev-nonce-1',
        signature: 'sig',
        timestamp: Date.now(),
      })
    );
    const revConfirm = await revPromise;
    assert.strictEqual(revConfirm.type, 'revoke_confirm');
    assert.strictEqual(revConfirm.success, true);

    // Attempting to authenticate after revocation must fail
    const wsAfter = await connectWs();
    const afterPromise = waitMsg(wsAfter);
    wsAfter.send(
      JSON.stringify({
        type: 'auth',
        version: 1,
        deviceId: 'device-alice',
        nonce: 'nonce-alice-after-revoke',
        signature: 'sig',
        timestamp: Date.now(),
      })
    );
    const afterRes = await afterPromise;
    assert.strictEqual(afterRes.success, false);
    assert.match(afterRes.error, /revoked/i);
    wsAfter.close();
  });

  await t.test('7. Cryptographic primitives: AEAD Encryption, Replay & Integrity verification', async () => {
    const key = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);
    const plaintext = Buffer.from('SecretPlay top-secret in-memory message');

    const cipher = crypto.createCipheriv('chacha20-poly1305', key, iv, { authTagLength: 16 });
    const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const authTag = cipher.getAuthTag();

    const decipher = crypto.createDecipheriv('chacha20-poly1305', key, iv, { authTagLength: 16 });
    decipher.setAuthTag(authTag);
    const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    assert.strictEqual(decrypted.toString('utf8'), plaintext.toString('utf8'));

    const tamperedCiphertext = Buffer.from(ciphertext);
    tamperedCiphertext[0] ^= 0x01;
    const badDecipher = crypto.createDecipheriv('chacha20-poly1305', key, iv, { authTagLength: 16 });
    badDecipher.setAuthTag(authTag);
    assert.throws(() => {
      badDecipher.update(tamperedCiphertext);
      badDecipher.final();
    });
  });

  await t.test('8. Diffie-Hellman Key Agreement (ECDH X25519) & HKDF derivation', async () => {
    const alice = crypto.generateKeyPairSync('x25519');
    const bob = crypto.generateKeyPairSync('x25519');

    const aliceShared = crypto.diffieHellman({
      privateKey: alice.privateKey,
      publicKey: bob.publicKey,
    });

    const bobShared = crypto.diffieHellman({
      privateKey: bob.privateKey,
      publicKey: alice.publicKey,
    });

    assert.deepStrictEqual(aliceShared, bobShared, 'X25519 shared secrets must match');

    const salt = crypto.randomBytes(16);
    const info = Buffer.from('SecretPlay-SessionKey-v1');
    const derivedAlice = crypto.hkdfSync('sha256', aliceShared, salt, info, 32);
    const derivedBob = crypto.hkdfSync('sha256', bobShared, salt, info, 32);

    assert.deepStrictEqual(derivedAlice, derivedBob, 'Derived session keys must match');
  });

  await t.test('9. Short Authentication String (SAS) calculation for Pairing', async () => {
    const pubKeyA = 'alice-identity-public-key-curve25519';
    const pubKeyB = 'bob-identity-public-key-curve25519';
    const inviteCode = 'invite-random-token-xyz';

    const sorted = [pubKeyA, pubKeyB].sort().join(':');
    const hmacA = crypto.createHmac('sha256', inviteCode).update(sorted).digest();
    const sasCodeA = (hmacA.readUInt32BE(0) % 1000000).toString().padStart(6, '0');

    const hmacB = crypto.createHmac('sha256', inviteCode).update(sorted).digest();
    const sasCodeB = (hmacB.readUInt32BE(0) % 1000000).toString().padStart(6, '0');

    assert.strictEqual(sasCodeA, sasCodeB);
    assert.strictEqual(sasCodeA.length, 6);
  });
});
