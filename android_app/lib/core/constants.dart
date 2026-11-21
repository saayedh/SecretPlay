class AppConstants {
  static const String appName = 'SecretPlay';
  static const String appVersion = '1.3.1';
  static const int appBuildNumber = 4;

  static const String cloudflareHttpBase =
      'https://secretplay-relay.enterprise-config-2026.workers.dev';

  // Network & Session (Jitter-tolerant for unstable mobile networks)
  static const int heartbeatIntervalMs = 10000;
  static const int sessionTimeoutMs = 45000;
  static const int pairingInvitationExpiryMinutes = 5;

  // Cryptography
  static const String sasHkdfInfo = 'SecretPlay-SAS-v1';
  static const String sessionKeyHkdfInfo = 'SecretPlay-SessionKey-v1';
  static const String signalKeyHkdfInfo = 'SecretPlay-SignalKey-v1';
  static const String recoveryHkdfInfo = 'SecretPlay-Recovery-v1';

  // Default Endpoints (Live Deployed Cloudflare Free-Tier Relay)
  static const String defaultCloudflareWss =
      'wss://secretplay-relay.enterprise-config-2026.workers.dev/ws';
  static const String defaultCloudflareUrl = defaultCloudflareWss;
  static const String defaultLocalServerHost = '192.168.137.1'; // Standard Windows Hotspot IP
  static const int defaultLocalServerPort = 8787;
  static const String defaultLocalUrl = 'ws://$defaultLocalServerHost:$defaultLocalServerPort/ws';

  // Storage Keys (Secure Storage only - never plain SharedPrefs)
  static const String keyDeviceId = 'sp_device_id';
  static const String keyIdentityPrivateKey = 'sp_id_priv_key';
  static const String keyIdentityPublicKey = 'sp_id_pub_key';
  static const String keyPeerDeviceId = 'sp_peer_device_id';
  static const String keyPeerPublicKey = 'sp_peer_pub_key';
  static const String keyPairToken = 'sp_pair_token';
  static const String keyAppPassphraseHash = 'sp_passphrase_hash';
  static const String keyNetworkMode = 'sp_net_mode';
  static const String keyCustomCloudUrl = 'sp_custom_cloud_url';
  static const String keyCustomLocalUrl = 'sp_custom_local_url';
  static const String keyBiometricsEnabled = 'sp_biometrics_enabled';
  static const String keyLanguageCode = 'sp_language_code';
  static const String keyContactsList = 'sp_contacts_list';
  static const String keyMySecretNumber = 'sp_my_secret_number';
  static const String keyDuressPinHash = 'sp_duress_pin_hash';
  static const String keyShakeToLockEnabled = 'sp_shake_to_lock';
}
