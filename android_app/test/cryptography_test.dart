import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:secretplay/cryptography/crypto_service.dart';
import 'package:secretplay/cryptography/recovery_crypto.dart';

void main() {
  group('SecretPlay Cryptography & Zero-Trust Protocol Tests', () {
    late CryptoService cryptoService;

    setUp(() {
      cryptoService = CryptoService();
    });

    test('1. Identity Keypair Generation, Seed Reconstruction, and 64-byte Combined Public Key Export', () async {
      final keyPair = await cryptoService.generateIdentityKeyPair();
      final privB64 = await cryptoService.exportPrivateKey(keyPair);
      final pubB64 = await cryptoService.exportPublicKey(keyPair);

      expect(privB64.isNotEmpty, true);
      expect(pubB64.isNotEmpty, true);
      expect(base64Decode(privB64).length, 32);
      expect(base64Decode(pubB64).length, 64); // 32B Ed25519 + 32B X25519 public bundle

      final reconstructed = await cryptoService.reconstructIdentityKeyPair(privB64);
      final reconstructedPub = await cryptoService.exportPublicKey(reconstructed);
      expect(reconstructedPub, pubB64);
    });

    test('2. End-to-End Encrypted Message Exchange and Authentication', () async {
      final aliceIdKeyPair = await cryptoService.generateIdentityKeyPair();
      final bobIdKeyPair = await cryptoService.generateIdentityKeyPair();

      final alicePub = await cryptoService.exportPublicKey(aliceIdKeyPair);
      final bobPub = await cryptoService.exportPublicKey(bobIdKeyPair);

      const sessionEpoch = 'test-epoch-101';
      const secretPlaintext = 'Top secret E2EE payload for authorized peer';

      // Alice encrypts for Bob
      final envelope = await cryptoService.encryptMessage(
        plaintext: secretPlaintext,
        recipientPublicIdentityKeyBase64: bobPub,
        senderIdentityKeyPair: aliceIdKeyPair,
        sessionEpoch: sessionEpoch,
      );

      expect(envelope.ciphertextBase64.isNotEmpty, true);
      expect(envelope.seq, 1);
      expect(envelope.signatureBase64.isNotEmpty, true);

      // Bob decrypts and verifies signature from Alice
      final decrypted = await cryptoService.decryptMessage(
        envelope: envelope,
        recipientIdentityKeyPair: bobIdKeyPair,
        senderPublicIdentityKeyBase64: alicePub,
        sessionEpoch: sessionEpoch,
      );

      expect(decrypted, secretPlaintext);
    });

    test('3. Modified Ciphertext Fails Authentication (Integrity Violation)', () async {
      final aliceIdKeyPair = await cryptoService.generateIdentityKeyPair();
      final bobIdKeyPair = await cryptoService.generateIdentityKeyPair();

      final alicePub = await cryptoService.exportPublicKey(aliceIdKeyPair);
      final bobPub = await cryptoService.exportPublicKey(bobIdKeyPair);
      const sessionEpoch = 'test-epoch-102';

      final envelope = await cryptoService.encryptMessage(
        plaintext: 'Valid Message',
        recipientPublicIdentityKeyBase64: bobPub,
        senderIdentityKeyPair: aliceIdKeyPair,
        sessionEpoch: sessionEpoch,
      );

      // Tamper 1 byte of ciphertext
      final rawCipher = base64Decode(envelope.ciphertextBase64);
      rawCipher[0] ^= 0x01;
      final tamperedEnvelope = EncryptedEnvelope(
        ciphertextBase64: base64Encode(rawCipher),
        ivBase64: envelope.ivBase64,
        authTagBase64: envelope.authTagBase64,
        ephemeralPubKeyBase64: envelope.ephemeralPubKeyBase64,
        seq: envelope.seq,
        signatureBase64: envelope.signatureBase64,
      );

      // Signature verification MUST reject before decryption
      expect(
        () async => await cryptoService.decryptMessage(
          envelope: tamperedEnvelope,
          recipientIdentityKeyPair: bobIdKeyPair,
          senderPublicIdentityKeyBase64: alicePub,
          sessionEpoch: sessionEpoch,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('4. Replayed Message with Stale Sequence Number is Rejected', () async {
      final aliceIdKeyPair = await cryptoService.generateIdentityKeyPair();
      final bobIdKeyPair = await cryptoService.generateIdentityKeyPair();

      final alicePub = await cryptoService.exportPublicKey(aliceIdKeyPair);
      final bobPub = await cryptoService.exportPublicKey(bobIdKeyPair);
      const sessionEpoch = 'test-epoch-103';

      final env1 = await cryptoService.encryptMessage(
        plaintext: 'Message 1',
        recipientPublicIdentityKeyBase64: bobPub,
        senderIdentityKeyPair: aliceIdKeyPair,
        sessionEpoch: sessionEpoch,
      );

      await cryptoService.decryptMessage(
        envelope: env1,
        recipientIdentityKeyPair: bobIdKeyPair,
        senderPublicIdentityKeyBase64: alicePub,
        sessionEpoch: sessionEpoch,
      );

      // Attempting to replay env1 again MUST fail replay check (envelope.seq <= _lastInSeq)
      expect(
        () async => await cryptoService.decryptMessage(
          envelope: env1,
          recipientIdentityKeyPair: bobIdKeyPair,
          senderPublicIdentityKeyBase64: alicePub,
          sessionEpoch: sessionEpoch,
        ),
        throwsA(predicate((e) => e.toString().contains('Replay attack detected'))),
      );
    });

    test('5. Short Authentication String (SAS) Symmetry & MitM Detection', () async {
      const pubA = 'AlicePublicKeyBase64Placeholder==';
      const pubB = 'BobPublicKeyBase64Placeholder====';
      const pubEve = 'EvePublicKeyBase64Placeholder====';
      const invitation = 'random-invitation-token-12345';

      final sasA = await cryptoService.computeSasCode(
        localPublicKeyBase64: pubA,
        remotePublicKeyBase64: pubB,
        invitationCode: invitation,
      );

      final sasB = await cryptoService.computeSasCode(
        localPublicKeyBase64: pubB,
        remotePublicKeyBase64: pubA,
        invitationCode: invitation,
      );

      final sasMitm = await cryptoService.computeSasCode(
        localPublicKeyBase64: pubA,
        remotePublicKeyBase64: pubEve,
        invitationCode: invitation,
      );

      expect(sasA, sasB);
      expect(sasA.length, 6);
      expect(int.tryParse(sasA), isNotNull);
      expect(sasA == sasMitm, false);
    });

    test('6. Encrypted Account Recovery Vault Export and Import without Chat History', () async {
      final recoveryService = RecoveryCryptoService();
      const passphrase = 'SuperStrongUserPassphrase!2026';

      final originalPackage = RecoveryPackage(
        deviceId: 'dev-alice-01',
        deviceIdentityPrivateKeyBase64: 'private-key-bytes',
        deviceIdentityPublicKeyBase64: 'public-key-bytes',
        pairedPeerPublicKeyBase64: 'peer-public-key-bytes',
        requiresReverification: true,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      // Verify zero chat history in JSON
      final jsonMap = originalPackage.toJson();
      expect(jsonMap.containsKey('messages'), false);
      expect(jsonMap.containsKey('history'), false);
      expect(jsonMap.containsKey('sessionKeys'), false);

      // Export encrypted vault (XChaCha20-Poly1305 24-byte nonce)
      final vault = await recoveryService.exportEncryptedRecoveryVault(
        package: originalPackage,
        passphrase: passphrase,
      );
      expect(base64Decode(vault.nonceBase64).length, 24);

      // Decrypt vault with correct passphrase
      final restored = await recoveryService.importEncryptedRecoveryVault(
        vault: vault,
        passphrase: passphrase,
      );

      expect(restored.deviceId, 'dev-alice-01');
      expect(restored.deviceIdentityPrivateKeyBase64, 'private-key-bytes');
      expect(restored.pairedPeerPublicKeyBase64, 'peer-public-key-bytes');
      expect(restored.requiresReverification, true);

      // Attempting decryption with incorrect passphrase MUST fail
      expect(
        () async => await recoveryService.importEncryptedRecoveryVault(
          vault: vault,
          passphrase: 'WrongPassword!',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('7. Authenticated WebRTC Signaling Encryption and Salted Passphrase Verification', () async {
      final alice = await cryptoService.generateIdentityKeyPair();
      final bob = await cryptoService.generateIdentityKeyPair();
      final alicePub = await cryptoService.exportPublicKey(alice);
      final bobPub = await cryptoService.exportPublicKey(bob);

      const sdpOffer = '{"type":"offer","sdp":"v=0\\r\\no=- 999 2 IN IP4 192.168.137.10"}';
      final sigEnv = await cryptoService.encryptSignalingPayload(
        plaintext: sdpOffer,
        recipientPublicIdentityKeyBase64: bobPub,
        senderIdentityKeyPair: alice,
        sessionEpoch: 'epoch-voice-55',
      );
      final decryptedSdp = await cryptoService.decryptSignalingPayload(
        envelope: sigEnv,
        recipientIdentityKeyPair: bob,
        senderPublicIdentityKeyBase64: alicePub,
        sessionEpoch: 'epoch-voice-55',
      );
      expect(decryptedSdp, sdpOffer);

      final hashed = await cryptoService.hashPassphrase('MySecretPass123');
      expect(hashed.contains('MySecretPass123'), false);
      expect(await cryptoService.verifyPassphrase('MySecretPass123', hashed), true);
      expect(await cryptoService.verifyPassphrase('WrongPass', hashed), false);
    });
  });
}
