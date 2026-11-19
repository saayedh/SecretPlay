import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class RecoveryPackage {
  final String version;
  final String deviceId;
  final String deviceIdentityPrivateKeyBase64;
  final String deviceIdentityPublicKeyBase64;
  final String pairedPeerPublicKeyBase64;
  final bool requiresReverification;
  final int createdAt;

  RecoveryPackage({
    this.version = '1.0',
    this.deviceId = '',
    required this.deviceIdentityPrivateKeyBase64,
    required this.deviceIdentityPublicKeyBase64,
    required this.pairedPeerPublicKeyBase64,
    this.requiresReverification = true,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'deviceId': deviceId,
        'privKey': deviceIdentityPrivateKeyBase64,
        'pubKey': deviceIdentityPublicKeyBase64,
        'peerKey': pairedPeerPublicKeyBase64,
        'requiresReverification': requiresReverification,
        'createdAt': createdAt,
        // ZERO CHAT MESSAGES, ZERO SESSION KEYS, ZERO MEDIA
      };

  factory RecoveryPackage.fromJson(Map<String, dynamic> json) => RecoveryPackage(
        version: json['version'] ?? '1.0',
        deviceId: json['deviceId'] ?? '',
        deviceIdentityPrivateKeyBase64: json['privKey'] ?? '',
        deviceIdentityPublicKeyBase64: json['pubKey'] ?? '',
        pairedPeerPublicKeyBase64: json['peerKey'] ?? '',
        requiresReverification: json['requiresReverification'] ?? true,
        createdAt: json['createdAt'] ?? 0,
      );
}

class EncryptedRecoveryVault {
  final String ciphertextBase64;
  final String saltBase64;
  final String nonceBase64;
  final String macBase64;

  EncryptedRecoveryVault({
    required this.ciphertextBase64,
    required this.saltBase64,
    required this.nonceBase64,
    required this.macBase64,
  });

  String serialize() => jsonEncode({
        'c': ciphertextBase64,
        's': saltBase64,
        'n': nonceBase64,
        'm': macBase64,
      });

  factory EncryptedRecoveryVault.deserialize(String jsonString) {
    final map = jsonDecode(jsonString);
    return EncryptedRecoveryVault(
      ciphertextBase64: map['c'],
      saltBase64: map['s'],
      nonceBase64: map['n'],
      macBase64: map['m'],
    );
  }
}

class RecoveryCryptoService {
  // XChaCha20-Poly1305 with 192-bit (24-byte) extended nonce
  final Cipher _aead = Xchacha20.poly1305Aead();

  /// Derives a 256-bit symmetric key from passphrase and salt using Argon2id (with PBKDF2 fallback)
  Future<SecretKey> _deriveKeyFromPassphrase(String passphrase, List<int> salt) async {
    try {
      final argon2 = Argon2id(
        memory: 16384,
        parallelism: 2,
        iterations: 2,
        hashLength: 32,
      );
      return await argon2.deriveKey(
        secretKey: SecretKey(utf8.encode(passphrase)),
        nonce: salt,
      );
    } catch (_) {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      );
      return await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(passphrase)),
        nonce: salt,
      );
    }
  }

  /// Encrypts identity recovery package using passphrase and XChaCha20-Poly1305
  Future<EncryptedRecoveryVault> exportEncryptedRecoveryVault({
    required RecoveryPackage package,
    required String passphrase,
  }) async {
    final rng = Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));

    final derivedKey = await _deriveKeyFromPassphrase(passphrase, salt);
    final payloadBytes = utf8.encode(jsonEncode(package.toJson()));

    final secretBox = await _aead.encrypt(
      payloadBytes,
      secretKey: derivedKey,
      nonce: _aead.newNonce(),
    );

    return EncryptedRecoveryVault(
      ciphertextBase64: base64Encode(secretBox.cipherText),
      saltBase64: base64Encode(salt),
      nonceBase64: base64Encode(secretBox.nonce),
      macBase64: base64Encode(secretBox.mac.bytes),
    );
  }

  /// Decrypts identity recovery package using passphrase and XChaCha20-Poly1305
  Future<RecoveryPackage> importEncryptedRecoveryVault({
    required EncryptedRecoveryVault vault,
    required String passphrase,
  }) async {
    final salt = base64Decode(vault.saltBase64);
    final derivedKey = await _deriveKeyFromPassphrase(passphrase, salt);

    final secretBox = SecretBox(
      base64Decode(vault.ciphertextBase64),
      nonce: base64Decode(vault.nonceBase64),
      mac: Mac(base64Decode(vault.macBase64)),
    );

    try {
      final decryptedBytes = await _aead.decrypt(secretBox, secretKey: derivedKey);
      final jsonMap = jsonDecode(utf8.decode(decryptedBytes)) as Map<String, dynamic>;
      return RecoveryPackage.fromJson(jsonMap);
    } catch (e) {
      throw Exception('Failed to decrypt recovery vault. Invalid passphrase or corrupt payload.');
    }
  }
}
