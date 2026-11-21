import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';

class KeystoreService {
  static final Map<String, String> _fallbackMemoryStore = {};
  final FlutterSecureStorage _storage;

  KeystoreService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
            );

  Future<String?> _read(String key) async {
    try {
      final val = await _storage.read(key: key);
      return val ?? _fallbackMemoryStore[key];
    } catch (_) {
      return _fallbackMemoryStore[key];
    }
  }

  Future<void> _write(String key, String value) async {
    _fallbackMemoryStore[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Fallback to in-memory storage on desktop/web simulator
    }
  }

  Future<void> _delete(String key) async {
    _fallbackMemoryStore.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }

  Future<String> getOrCreateDeviceId() async {
    final existing = await _read(AppConstants.keyDeviceId);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final id = 'dev-${const Uuid().v4()}';
    await _write(AppConstants.keyDeviceId, id);
    return id;
  }

  Future<void> saveIdentityKeyPair({
    required String privateKeyBase64,
    required String publicKeyBase64,
  }) async {
    await _write(AppConstants.keyIdentityPrivateKey, privateKeyBase64);
    await _write(AppConstants.keyIdentityPublicKey, publicKeyBase64);
  }

  Future<String?> getIdentityPrivateKey() async {
    return await _read(AppConstants.keyIdentityPrivateKey);
  }

  Future<String?> getIdentityPublicKey() async {
    return await _read(AppConstants.keyIdentityPublicKey);
  }

  Future<void> savePairedPeer({
    required String peerDeviceId,
    required String peerPublicKeyBase64,
  }) async {
    await _write(AppConstants.keyPeerDeviceId, peerDeviceId);
    await _write(AppConstants.keyPeerPublicKey, peerPublicKeyBase64);
  }

  Future<String?> getPeerDeviceId() async {
    return await _read(AppConstants.keyPeerDeviceId);
  }

  Future<String?> getPeerPublicKey() async {
    return await _read(AppConstants.keyPeerPublicKey);
  }

  Future<void> savePairToken(String token) async {
    await _write(AppConstants.keyPairToken, token.trim().toUpperCase());
  }

  Future<String?> getPairToken() async {
    return await _read(AppConstants.keyPairToken);
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
    await _write(AppConstants.keyAppPassphraseHash, hash);
  }

  Future<String?> getPassphraseHash() async {
    return await _read(AppConstants.keyAppPassphraseHash);
  }

  Future<bool> isPassphraseConfigured() async {
    final hash = await getPassphraseHash();
    return hash != null && hash.isNotEmpty;
  }

  Future<void> saveNetworkMode(String modeName) async {
    await _write(AppConstants.keyNetworkMode, modeName);
  }

  Future<String?> getNetworkMode() async {
    return await _read(AppConstants.keyNetworkMode);
  }

  Future<void> saveCustomCloudUrl(String url) async {
    await _write(AppConstants.keyCustomCloudUrl, url);
  }

  Future<String?> getCustomCloudUrl() async {
    return await _read(AppConstants.keyCustomCloudUrl);
  }

  Future<void> saveCustomLocalUrl(String url) async {
    await _write(AppConstants.keyCustomLocalUrl, url);
  }

  Future<String?> getCustomLocalUrl() async {
    return await _read(AppConstants.keyCustomLocalUrl);
  }

  Future<void> saveLanguageCode(String code) async {
    await _write(AppConstants.keyLanguageCode, code);
  }

  Future<String?> getLanguageCode() async {
    return await _read(AppConstants.keyLanguageCode);
  }

  Future<void> saveMySecretNumber(String secretNumber) async {
    await _write(AppConstants.keyMySecretNumber, secretNumber.trim().toUpperCase());
  }

  Future<String?> getMySecretNumber() async {
    return await _read(AppConstants.keyMySecretNumber);
  }

  Future<void> saveContactsJson(String jsonList) async {
    await _write(AppConstants.keyContactsList, jsonList);
  }

  Future<String?> getContactsJson() async {
    return await _read(AppConstants.keyContactsList);
  }

  Future<void> saveDuressPinHash(String hash) async {
    await _write(AppConstants.keyDuressPinHash, hash);
  }

  Future<String?> getDuressPinHash() async {
    return await _read(AppConstants.keyDuressPinHash);
  }

  Future<void> saveRoomChatHistory(String roomToken, String jsonMessages) async {
    final key = 'sp_chat_hist_${roomToken.trim().toUpperCase()}';
    await _write(key, jsonMessages);
  }

  Future<String?> getRoomChatHistory(String roomToken) async {
    final key = 'sp_chat_hist_${roomToken.trim().toUpperCase()}';
    return await _read(key);
  }

  Future<void> deleteRoomChatHistory(String roomToken) async {
    final key = 'sp_chat_hist_${roomToken.trim().toUpperCase()}';
    await _delete(key);
  }

  Future<void> saveRoomOutbox(String roomToken, String jsonEnvelopes) async {
    final key = 'sp_chat_outbox_${roomToken.trim().toUpperCase()}';
    await _write(key, jsonEnvelopes);
  }

  Future<String?> getRoomOutbox(String roomToken) async {
    final key = 'sp_chat_outbox_${roomToken.trim().toUpperCase()}';
    return await _read(key);
  }

  Future<void> deleteRoomOutbox(String roomToken) async {
    final key = 'sp_chat_outbox_${roomToken.trim().toUpperCase()}';
    await _delete(key);
  }

  Future<void> revokePairing() async {
    await _delete(AppConstants.keyPeerDeviceId);
    await _delete(AppConstants.keyPeerPublicKey);
    await _delete(AppConstants.keyPairToken);
  }

  Future<void> fullWipe() async {
    _fallbackMemoryStore.clear();
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }
}
