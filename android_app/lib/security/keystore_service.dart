import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';

class KeystoreService {
  final FlutterSecureStorage _storage;

  KeystoreService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
            );

  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: AppConstants.keyDeviceId);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final id = 'dev-${const Uuid().v4()}';
    await _storage.write(key: AppConstants.keyDeviceId, value: id);
    return id;
  }

  Future<void> saveIdentityKeyPair({
    required String privateKeyBase64,
    required String publicKeyBase64,
  }) async {
    await _storage.write(key: AppConstants.keyIdentityPrivateKey, value: privateKeyBase64);
    await _storage.write(key: AppConstants.keyIdentityPublicKey, value: publicKeyBase64);
  }

  Future<String?> getIdentityPrivateKey() async {
    return await _storage.read(key: AppConstants.keyIdentityPrivateKey);
  }

  Future<String?> getIdentityPublicKey() async {
    return await _storage.read(key: AppConstants.keyIdentityPublicKey);
  }

  Future<void> savePairedPeer({
    required String peerDeviceId,
    required String peerPublicKeyBase64,
  }) async {
    await _storage.write(key: AppConstants.keyPeerDeviceId, value: peerDeviceId);
    await _storage.write(key: AppConstants.keyPeerPublicKey, value: peerPublicKeyBase64);
  }

  Future<String?> getPeerDeviceId() async {
    return await _storage.read(key: AppConstants.keyPeerDeviceId);
  }

  Future<String?> getPeerPublicKey() async {
    return await _storage.read(key: AppConstants.keyPeerPublicKey);
  }

  Future<void> savePairToken(String token) async {
    await _storage.write(key: AppConstants.keyPairToken, value: token.trim().toUpperCase());
  }

  Future<String?> getPairToken() async {
    return await _storage.read(key: AppConstants.keyPairToken);
  }

  Future<bool> hasPairTokenOrPeer() async {
    final token = await getPairToken();
    if (token != null && token.trim().isNotEmpty) return true;
    return await isPaired();
  }

  Future<bool> isPaired() async {
    final peerKey = await getPeerPublicKey();
    return peerKey != null && peerKey.isNotEmpty;
  }

  Future<void> savePassphraseHash(String hash) async {
    await _storage.write(key: AppConstants.keyAppPassphraseHash, value: hash);
  }

  Future<String?> getPassphraseHash() async {
    return await _storage.read(key: AppConstants.keyAppPassphraseHash);
  }

  Future<bool> isPassphraseConfigured() async {
    final hash = await getPassphraseHash();
    return hash != null && hash.isNotEmpty;
  }

  Future<void> saveNetworkMode(String modeName) async {
    await _storage.write(key: AppConstants.keyNetworkMode, value: modeName);
  }

  Future<String?> getNetworkMode() async {
    return await _storage.read(key: AppConstants.keyNetworkMode);
  }

  Future<void> saveCustomCloudUrl(String url) async {
    await _storage.write(key: AppConstants.keyCustomCloudUrl, value: url);
  }

  Future<String?> getCustomCloudUrl() async {
    return await _storage.read(key: AppConstants.keyCustomCloudUrl);
  }

  Future<void> saveCustomLocalUrl(String url) async {
    await _storage.write(key: AppConstants.keyCustomLocalUrl, value: url);
  }

  Future<String?> getCustomLocalUrl() async {
    return await _storage.read(key: AppConstants.keyCustomLocalUrl);
  }

  Future<void> revokePairing() async {
    await _storage.delete(key: AppConstants.keyPeerDeviceId);
    await _storage.delete(key: AppConstants.keyPeerPublicKey);
    await _storage.delete(key: AppConstants.keyPairToken);
  }

  Future<void> fullWipe() async {
    await _storage.deleteAll();
  }
}
