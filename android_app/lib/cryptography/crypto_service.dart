import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../core/constants.dart';

class EncryptedEnvelope {
  final String ciphertextBase64;
  final String ivBase64;
  final String authTagBase64;
  final String ephemeralPubKeyBase64;
  final int seq;
  final String signatureBase64;

  EncryptedEnvelope({
    required this.ciphertextBase64,
    required this.ivBase64,
    required this.authTagBase64,
    required this.ephemeralPubKeyBase64,
    required this.seq,
    required this.signatureBase64,
  });
}

class CryptoService {
  final Ed25519 _ed25519 = Ed25519();
  final X25519 _x25519 = X25519();
  final Cipher _aead = Chacha20.poly1305Aead();

  int _localOutSeq = 0;
  int _lastInSeq = 0;
  int _localSignalOutSeq = 0;
  int _lastSignalInSeq = 0;

  void resetSequence() {
    _localOutSeq = 0;
    _lastInSeq = 0;
    _localSignalOutSeq = 0;
    _lastSignalInSeq = 0;
  }

  void resetInboundSequence() {
    _lastInSeq = 0;
    _lastSignalInSeq = 0;
  }

  void resetMessageInboundSequence() {
    _lastInSeq = 0;
  }

  void resetSignalInboundSequence() {
    _lastSignalInSeq = 0;
  }

  /// Generates a long-term Ed25519 identity keypair backed by a 32-byte cryptographic seed
  Future<SimpleKeyPair> generateIdentityKeyPair() async {
    return await _ed25519.newKeyPair();
  }

  /// Reconstructs the Ed25519 identity keypair from a Base64-encoded 32-byte private seed
  Future<SimpleKeyPair> reconstructIdentityKeyPair(String privateKeyBase64) async {
    final seedBytes = base64Decode(privateKeyBase64);
    return await _ed25519.newKeyPairFromSeed(seedBytes);
  }

  /// Deterministically derives the paired X25519 key-agreement keypair from the 32-byte identity seed
  Future<SimpleKeyPair> _deriveX25519KeyPair(SimpleKeyPair ed25519KeyPair) async {
    final seedBytes = await ed25519KeyPair.extractPrivateKeyBytes();
    return await _x25519.newKeyPairFromSeed(seedBytes);
  }

  /// Exports 32-byte private identity seed to Base64
  Future<String> exportPrivateKey(SimpleKeyPair keyPair) async {
    final data = await keyPair.extractPrivateKeyBytes();
    return base64Encode(data);
  }

  /// Exports a combined 64-byte public identity bundle: [32B Ed25519 pub || 32B X25519 pub] in Base64
  Future<String> exportPublicKey(SimpleKeyPair keyPair) async {
    final edPubKey = await keyPair.extractPublicKey();
    final xKeyPair = await _deriveX25519KeyPair(keyPair);
    final xPubKey = await xKeyPair.extractPublicKey();
    final combined = <int>[...edPubKey.bytes, ...xPubKey.bytes];
    return base64Encode(combined);
  }

  SimplePublicKey _extractEd25519PublicKey(String publicKeyBase64) {
    final bytes = base64Decode(publicKeyBase64);
    if (bytes.length >= 32) {
      return SimplePublicKey(bytes.sublist(0, 32), type: KeyPairType.ed25519);
    }
    throw Exception('Invalid Ed25519 public key length: ${bytes.length}');
  }

  SimplePublicKey _extractX25519PublicKey(String publicKeyBase64) {
    final bytes = base64Decode(publicKeyBase64);
    if (bytes.length >= 64) {
      return SimplePublicKey(bytes.sublist(32, 64), type: KeyPairType.x25519);
    }
    if (bytes.length == 32) {
      return SimplePublicKey(bytes, type: KeyPairType.x25519);
    }
    throw Exception('Invalid X25519 public key length: ${bytes.length}');
  }

  /// Signs a WebSocket authentication challenge `${deviceId}:${nonce}:${timestamp}` with Ed25519
  Future<String> signAuthChallenge({
    required SimpleKeyPair identityKeyPair,
    required String deviceId,
    required String nonce,
    required int timestamp,
  }) async {
    final payload = utf8.encode('$deviceId:$nonce:$timestamp');
    final sig = await _ed25519.sign(payload, keyPair: identityKeyPair);
    return base64Encode(sig.bytes);
  }

  /// Salted passphrase derivation (Argon2id with PBKDF2-HMAC-SHA256 fallback)
  Future<String> hashPassphrase(String passphrase) async {
    final rng = Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));
    return await _hashPassphraseWithSalt(passphrase, salt);
  }

  Future<String> _hashPassphraseWithSalt(String passphrase, List<int> salt) async {
    try {
      final argon2 = Argon2id(
        memory: 16384,
        parallelism: 2,
        iterations: 2,
        hashLength: 32,
      );
      final key = await argon2.deriveKeyFromPassword(
        password: passphrase,
        nonce: salt,
      );
      final hashBytes = await key.extractBytes();
      return 'argon2id\$${base64Encode(salt)}\$${base64Encode(hashBytes)}';
    } catch (_) {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      );
      final key = await pbkdf2.deriveKeyFromPassword(
        password: passphrase,
        nonce: salt,
      );
      final hashBytes = await key.extractBytes();
      return 'pbkdf2\$${base64Encode(salt)}\$${base64Encode(hashBytes)}';
    }
  }

  /// Constant-time passphrase verification against stored salted hash
  Future<bool> verifyPassphrase(String passphrase, String storedHash) async {
    if (!storedHash.contains('\$')) {
      return false;
    }
    final parts = storedHash.split('\$');
    if (parts.length != 3) return false;
    final alg = parts[0];
    final salt = base64Decode(parts[1]);
    final expectedBytes = base64Decode(parts[2]);

    List<int> derivedBytes;
    if (alg == 'argon2id') {
      try {
        final argon2 = Argon2id(
          memory: 16384,
          parallelism: 2,
          iterations: 2,
          hashLength: 32,
        );
        final key = await argon2.deriveKeyFromPassword(password: passphrase, nonce: salt);
        derivedBytes = await key.extractBytes();
      } catch (_) {
        return false;
      }
    } else {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      );
      final key = await pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
      derivedBytes = await key.extractBytes();
    }

    if (derivedBytes.length != expectedBytes.length) return false;
    int diff = 0;
    for (int i = 0; i < derivedBytes.length; i++) {
      diff |= derivedBytes[i] ^ expectedBytes[i];
    }
    return diff == 0;
  }

  /// Encrypts an outgoing message using Ephemeral X25519 ECDH + HKDF-SHA256 + ChaCha20-Poly1305 AEAD
  Future<EncryptedEnvelope> encryptMessage({
    required String plaintext,
    required String recipientPublicIdentityKeyBase64,
    required SimpleKeyPair senderIdentityKeyPair,
    required String sessionEpoch,
  }) async {
    _localOutSeq++;
    return _encryptEnvelopeInternal(
      plaintext: plaintext,
      recipientPublicIdentityKeyBase64: recipientPublicIdentityKeyBase64,
      senderIdentityKeyPair: senderIdentityKeyPair,
      sessionEpoch: sessionEpoch,
      seq: _localOutSeq,
      hkdfInfo: AppConstants.sessionKeyHkdfInfo,
    );
  }

  /// Decrypts and authenticates an incoming chat message
  Future<String> decryptMessage({
    required EncryptedEnvelope envelope,
    required SimpleKeyPair recipientIdentityKeyPair,
    required String senderPublicIdentityKeyBase64,
    required String sessionEpoch,
  }) async {
    if (envelope.seq <= _lastInSeq) {
      throw Exception('Replay attack detected: sequence ${envelope.seq} <= last seen $_lastInSeq');
    }
    final plain = await _decryptEnvelopeInternal(
      envelope: envelope,
      recipientIdentityKeyPair: recipientIdentityKeyPair,
      senderPublicIdentityKeyBase64: senderPublicIdentityKeyBase64,
      sessionEpoch: sessionEpoch,
      hkdfInfo: AppConstants.sessionKeyHkdfInfo,
    );
    _lastInSeq = envelope.seq;
    return plain;
  }

  /// Encrypts a WebRTC signaling payload (SDP offer/answer or ICE candidate)
  Future<EncryptedEnvelope> encryptSignalingPayload({
    required String plaintext,
    required String recipientPublicIdentityKeyBase64,
    required SimpleKeyPair senderIdentityKeyPair,
    required String sessionEpoch,
  }) async {
    _localSignalOutSeq++;
    return _encryptEnvelopeInternal(
      plaintext: plaintext,
      recipientPublicIdentityKeyBase64: recipientPublicIdentityKeyBase64,
      senderIdentityKeyPair: senderIdentityKeyPair,
      sessionEpoch: sessionEpoch,
      seq: _localSignalOutSeq,
      hkdfInfo: AppConstants.signalKeyHkdfInfo,
    );
  }

  /// Decrypts and authenticates an incoming WebRTC signaling payload
  Future<String> decryptSignalingPayload({
    required EncryptedEnvelope envelope,
    required SimpleKeyPair recipientIdentityKeyPair,
    required String senderPublicIdentityKeyBase64,
    required String sessionEpoch,
  }) async {
    if (envelope.seq <= _lastSignalInSeq) {
      throw Exception('Signaling replay attack detected: sequence ${envelope.seq} <= $_lastSignalInSeq');
    }
    final plain = await _decryptEnvelopeInternal(
      envelope: envelope,
      recipientIdentityKeyPair: recipientIdentityKeyPair,
      senderPublicIdentityKeyBase64: senderPublicIdentityKeyBase64,
      sessionEpoch: sessionEpoch,
      hkdfInfo: AppConstants.signalKeyHkdfInfo,
    );
    _lastSignalInSeq = envelope.seq;
    return plain;
  }

  Future<EncryptedEnvelope> _encryptEnvelopeInternal({
    required String plaintext,
    required String recipientPublicIdentityKeyBase64,
    required SimpleKeyPair senderIdentityKeyPair,
    required String sessionEpoch,
    required int seq,
    required String hkdfInfo,
  }) async {
    // 1. Generate ephemeral X25519 keypair
    final ephemeralKeyPair = await _x25519.newKeyPair();
    final ephemeralPubKey = await ephemeralKeyPair.extractPublicKey();

    // 2. Extract recipient X25519 public key from identity bundle
    final recipientX25519PubKey = _extractX25519PublicKey(recipientPublicIdentityKeyBase64);

    // 3. Perform ECDH Diffie-Hellman
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: recipientX25519PubKey,
    );

    // 4. HKDF derivation of 256-bit symmetric encryption key bound to sessionEpoch
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derivedSecret = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(sessionEpoch),
      info: utf8.encode(hkdfInfo),
    );

    // 5. Encrypt with ChaCha20-Poly1305 AEAD
    final plainBytes = utf8.encode(plaintext);
    final secretBox = await _aead.encrypt(
      plainBytes,
      secretKey: derivedSecret,
      nonce: _aead.newNonce(),
    );

    final cipherB64 = base64Encode(secretBox.cipherText);
    final ivB64 = base64Encode(secretBox.nonce);

    // 6. Digital signature over the envelope to guarantee sender authenticity
    final envelopeToSign = utf8.encode('$cipherB64:$ivB64:$seq:$sessionEpoch');
    final signature = await _ed25519.sign(envelopeToSign, keyPair: senderIdentityKeyPair);

    return EncryptedEnvelope(
      ciphertextBase64: cipherB64,
      ivBase64: ivB64,
      authTagBase64: base64Encode(secretBox.mac.bytes),
      ephemeralPubKeyBase64: base64Encode(ephemeralPubKey.bytes),
      seq: seq,
      signatureBase64: base64Encode(signature.bytes),
    );
  }

  Future<String> _decryptEnvelopeInternal({
    required EncryptedEnvelope envelope,
    required SimpleKeyPair recipientIdentityKeyPair,
    required String senderPublicIdentityKeyBase64,
    required String sessionEpoch,
    required String hkdfInfo,
  }) async {
    // 1. Verify Ed25519 signature before attempting decryption
    final senderEdPubKey = _extractEd25519PublicKey(senderPublicIdentityKeyBase64);

    final signedBytes = utf8.encode(
      '${envelope.ciphertextBase64}:${envelope.ivBase64}:${envelope.seq}:$sessionEpoch',
    );
    final sig = Signature(
      base64Decode(envelope.signatureBase64),
      publicKey: senderEdPubKey,
    );

    final isValidSig = await _ed25519.verify(signedBytes, signature: sig);
    if (!isValidSig) {
      throw Exception('Cryptographic signature verification failed! Message was tampered or forged.');
    }

    // 2. Ephemeral ECDH key agreement using recipient's X25519 keypair derived from identity seed
    final ephemeralPubBytes = base64Decode(envelope.ephemeralPubKeyBase64);
    final ephemeralPubKey = SimplePublicKey(ephemeralPubBytes, type: KeyPairType.x25519);
    final recipientX25519KeyPair = await _deriveX25519KeyPair(recipientIdentityKeyPair);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: recipientX25519KeyPair,
      remotePublicKey: ephemeralPubKey,
    );

    // 3. HKDF derivation bound to sessionEpoch
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derivedSecret = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(sessionEpoch),
      info: utf8.encode(hkdfInfo),
    );

    // 4. Authenticated AEAD Decryption
    final secretBox = SecretBox(
      base64Decode(envelope.ciphertextBase64),
      nonce: base64Decode(envelope.ivBase64),
      mac: Mac(base64Decode(envelope.authTagBase64)),
    );

    final decryptedBytes = await _aead.decrypt(secretBox, secretKey: derivedSecret);
    return utf8.decode(decryptedBytes);
  }

  /// Computes Short Authentication String (SAS) 6-digit code bound to both devices' public keys
  Future<String> computeSasCode({
    required String localPublicKeyBase64,
    required String remotePublicKeyBase64,
    required String invitationCode,
  }) async {
    final hmac = Hmac.sha256();
    final secretKey = SecretKey(utf8.encode(invitationCode));

    // Lexicographically order public keys so both devices produce the exact same SAS
    final list = [localPublicKeyBase64, remotePublicKeyBase64]..sort();
    final combinedData = utf8.encode(list.join(':'));

    final mac = await hmac.calculateMac(combinedData, secretKey: secretKey);
    final bytes = mac.bytes;

    // Convert first 4 bytes to 6-digit integer
    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
    final num = byteData.getUint32(0, Endian.big) % 1000000;
    return num.toString().padLeft(6, '0');
  }
}
