const test = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');
const {
  generateIdentityBundle,
  reconstructIdentityBundle,
  signAuthChallenge,
  verifyAuthChallenge,
  ReplayGuard,
  encryptEnvelope,
  decryptEnvelope,
  computeSasCode,
  exportRecoveryVault,
  importRecoveryVault,
  SIGNAL_KEY_HKDF_INFO,
} = require('../dist/index');

test('SecretPlay crypto_core Comprehensive Test Suite', async (t) => {
  await t.test('1. Identity generation, seed reconstruction, and 64-byte public key encoding', () => {
    const id = generateIdentityBundle();
    const rawCombined = Buffer.from(id.publicKeyBase64, 'base64');
    assert.strictEqual(rawCombined.length, 64, 'Combined public key must be 32B Ed25519 + 32B X25519');
    assert.strictEqual(Buffer.from(id.ed25519PublicKeyBase64, 'base64').length, 32);
    assert.strictEqual(Buffer.from(id.x25519PublicKeyBase64, 'base64').length, 32);

    const reconstructed = reconstructIdentityBundle(id.seedBase64);
    assert.strictEqual(reconstructed.publicKeyBase64, id.publicKeyBase64);
  });

  await t.test('2. Signed authentication challenge verification, skew rejection, and nonce replay guard', () => {
    const alice = generateIdentityBundle();
    const guard = new ReplayGuard(60_000, 100);
    const now = Date.now();
    const nonce = crypto.randomBytes(16).toString('hex');

    const sig = signAuthChallenge(alice, 'device-alice', nonce, now);
    const check1 = verifyAuthChallenge({
      publicKeyBase64: alice.publicKeyBase64,
      deviceId: 'device-alice',
      nonce,
      timestamp: now,
      signatureBase64: sig,
      nowMs: now,
    });
    assert.strictEqual(check1.valid, true);
    assert.strictEqual(guard.checkAndRecordNonce(nonce, now), true);
    assert.strictEqual(guard.checkAndRecordNonce(nonce, now), false, 'Replayed nonce must be rejected');

    // Wrong deviceId fails verification
    const wrongDevice = verifyAuthChallenge({
      publicKeyBase64: alice.publicKeyBase64,
      deviceId: 'device-eve',
      nonce,
      timestamp: now,
      signatureBase64: sig,
      nowMs: now,
    });
    assert.strictEqual(wrongDevice.valid, false);

    // Expired timestamp fails verification
    const expired = verifyAuthChallenge({
      publicKeyBase64: alice.publicKeyBase64,
      deviceId: 'device-alice',
      nonce: 'fresh-nonce-1234',
      timestamp: now - 120_000,
      signatureBase64: signAuthChallenge(alice, 'device-alice', 'fresh-nonce-1234', now - 120_000),
      nowMs: now,
    });
    assert.strictEqual(expired.valid, false);
    assert.strictEqual(expired.reason, 'auth_timestamp_out_of_window');
  });

  await t.test('3. End-to-end encrypted message exchange (X25519 + HKDF-SHA256 + ChaCha20-Poly1305 + Ed25519)', () => {
    const alice = generateIdentityBundle();
    const bob = generateIdentityBundle();
    const epoch = 'epoch-abc-123';

    const envelope = encryptEnvelope({
      plaintext: 'Hello Bob — strictly ephemeral E2EE message!',
      recipientPublicKeyBase64: bob.publicKeyBase64,
      senderIdentity: alice,
      sessionEpoch: epoch,
      seq: 1,
    });

    const plaintext = decryptEnvelope({
      envelope,
      recipientIdentity: bob,
      senderPublicKeyBase64: alice.publicKeyBase64,
      sessionEpoch: epoch,
      lastSeq: 0,
    });

    assert.strictEqual(plaintext, 'Hello Bob — strictly ephemeral E2EE message!');
  });

  await t.test('4. Tampered ciphertext, IV, authTag, and forged signature are rejected', () => {
    const alice = generateIdentityBundle();
    const bob = generateIdentityBundle();
    const eve = generateIdentityBundle();
    const epoch = 'epoch-tamper-1';

    const env = encryptEnvelope({
      plaintext: 'Integrity critical payload',
      recipientPublicKeyBase64: bob.publicKeyBase64,
      senderIdentity: alice,
      sessionEpoch: epoch,
      seq: 1,
    });

    // Tamper ciphertext
    const badCt = Buffer.from(env.ciphertext, 'base64');
    badCt[0] ^= 0xff;
    assert.throws(() => {
      decryptEnvelope({
        envelope: { ...env, ciphertext: badCt.toString('base64') },
        recipientIdentity: bob,
        senderPublicKeyBase64: alice.publicKeyBase64,
        sessionEpoch: epoch,
        lastSeq: 0,
      });
    }, /Signature verification failed/);

    // Tamper authTag (requires matching signature over ct/iv/seq/epoch, or re-sign by eve -> still fails sender check)
    const badTag = Buffer.from(env.authTag, 'base64');
    badTag[0] ^= 0xff;
    assert.throws(() => {
      decryptEnvelope({
        envelope: { ...env, authTag: badTag.toString('base64') },
        recipientIdentity: bob,
        senderPublicKeyBase64: alice.publicKeyBase64,
        sessionEpoch: epoch,
        lastSeq: 0,
      });
    });

    // Wrong sender public key (Eve impersonating Alice)
    assert.throws(() => {
      decryptEnvelope({
        envelope: env,
        recipientIdentity: bob,
        senderPublicKeyBase64: eve.publicKeyBase64,
        sessionEpoch: epoch,
        lastSeq: 0,
      });
    }, /Signature verification failed/);
  });

  await t.test('5. Replay sequence number and wrong sessionEpoch rejection', () => {
    const alice = generateIdentityBundle();
    const bob = generateIdentityBundle();
    const epoch = 'epoch-replay-1';

    const env1 = encryptEnvelope({
      plaintext: 'Msg 1',
      recipientPublicKeyBase64: bob.publicKeyBase64,
      senderIdentity: alice,
      sessionEpoch: epoch,
      seq: 1,
    });

    assert.strictEqual(
      decryptEnvelope({
        envelope: env1,
        recipientIdentity: bob,
        senderPublicKeyBase64: alice.publicKeyBase64,
        sessionEpoch: epoch,
        lastSeq: 0,
      }),
      'Msg 1'
    );

    // Replay seq=1 when lastSeq=1 fails
    assert.throws(() => {
      decryptEnvelope({
        envelope: env1,
        recipientIdentity: bob,
        senderPublicKeyBase64: alice.publicKeyBase64,
        sessionEpoch: epoch,
        lastSeq: 1,
      });
    }, /Replay attack detected/);

    // Wrong epoch fails signature check
    assert.throws(() => {
      decryptEnvelope({
        envelope: env1,
        recipientIdentity: bob,
        senderPublicKeyBase64: alice.publicKeyBase64,
        sessionEpoch: 'epoch-different',
        lastSeq: 0,
      });
    }, /Signature verification failed/);
  });

  await t.test('6. Encrypted WebRTC signaling envelope protection and replay defense', () => {
    const alice = generateIdentityBundle();
    const bob = generateIdentityBundle();
    const epoch = 'epoch-voice-1';
    const sdpOffer = JSON.stringify({ type: 'offer', sdp: 'v=0\r\no=- 123 2 IN IP4 192.168.137.10\r\n' });

    const sigEnv = encryptEnvelope({
      plaintext: sdpOffer,
      recipientPublicKeyBase64: bob.publicKeyBase64,
      senderIdentity: alice,
      sessionEpoch: epoch,
      seq: 1,
      hkdfInfo: SIGNAL_KEY_HKDF_INFO,
    });

    const decryptedSdp = decryptEnvelope({
      envelope: sigEnv,
      recipientIdentity: bob,
      senderPublicKeyBase64: alice.publicKeyBase64,
      sessionEpoch: epoch,
      lastSeq: 0,
      hkdfInfo: SIGNAL_KEY_HKDF_INFO,
    });
    assert.strictEqual(decryptedSdp, sdpOffer);

    // Replay signaling fails
    assert.throws(() => {
      decryptEnvelope({
        envelope: sigEnv,
        recipientIdentity: bob,
        senderPublicKeyBase64: alice.publicKeyBase64,
        sessionEpoch: epoch,
        lastSeq: 1,
        hkdfInfo: SIGNAL_KEY_HKDF_INFO,
      });
    }, /Replay attack detected/);
  });

  await t.test('7. SAS 6-digit symmetry and MitM key substitution detection', () => {
    const alice = generateIdentityBundle();
    const bob = generateIdentityBundle();
    const mitm = generateIdentityBundle();
    const inviteCode = 'one-time-invite-xyz-789';

    const sasAlice = computeSasCode({
      pubKeyA: alice.publicKeyBase64,
      pubKeyB: bob.publicKeyBase64,
      deviceAId: 'dev-a',
      deviceBId: 'dev-b',
      invitationCode: inviteCode,
    });

    const sasBob = computeSasCode({
      pubKeyA: bob.publicKeyBase64,
      pubKeyB: alice.publicKeyBase64,
      deviceAId: 'dev-b',
      deviceBId: 'dev-a',
      invitationCode: inviteCode,
    });

    assert.strictEqual(sasAlice, sasBob);
    assert.match(sasAlice, /^\d{6}$/);

    // MitM substitutes Bob's key on Alice's side
    const sasMitm = computeSasCode({
      pubKeyA: alice.publicKeyBase64,
      pubKeyB: mitm.publicKeyBase64,
      deviceAId: 'dev-a',
      deviceBId: 'dev-b',
      invitationCode: inviteCode,
    });
    assert.notStrictEqual(sasAlice, sasMitm, 'MitM key substitution must change SAS code');
  });

  await t.test('8. Encrypted recovery vault export/import, wrong passphrase failure, and zero chat history', () => {
    const alice = generateIdentityBundle();
    const bob = generateIdentityBundle();
    const passphrase = 'correct-horse-battery-staple!';

    const serialized = exportRecoveryVault({
      identity: alice,
      deviceId: 'dev-alice',
      peerDeviceId: 'dev-bob',
      peerPublicKeyBase64: bob.publicKeyBase64,
      passphrase,
    });

    const restored = importRecoveryVault({
      serializedVault: serialized,
      passphrase,
    });

    assert.strictEqual(restored.deviceId, 'dev-alice');
    assert.strictEqual(restored.privKey, alice.seedBase64);
    assert.strictEqual(restored.pubKey, alice.publicKeyBase64);
    assert.strictEqual(restored.peerKey, bob.publicKeyBase64);
    assert.strictEqual(restored.requiresReverification, true);
    assert.strictEqual('messages' in restored, false);
    assert.strictEqual('history' in restored, false);
    assert.strictEqual('sessionKeys' in restored, false);

    assert.throws(() => {
      importRecoveryVault({
        serializedVault: serialized,
        passphrase: 'wrong-passphrase!',
      });
    });
  });
});
