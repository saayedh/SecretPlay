import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../security/keystore_service.dart';

enum NetworkMode {
  cloud, // Cloudflare Workers + Durable Objects
  local, // Laptop local Wi-Fi / Hotspot server
}

class NetworkConfig {
  final NetworkMode mode;
  final String cloudWssUrl;
  final String localWsHost;
  final int localWsPort;
  final String pairToken;

  const NetworkConfig({
    this.mode = NetworkMode.cloud,
    this.cloudWssUrl = AppConstants.defaultCloudflareWss,
    this.localWsHost = AppConstants.defaultLocalServerHost,
    this.localWsPort = AppConstants.defaultLocalServerPort,
    this.pairToken = '',
  });

  String get cloudflareUrl => cloudWssUrl;

  String get localServerUrl => 'ws://$localWsHost:$localWsPort/ws';

  String get activeWsUrl {
    final base = mode == NetworkMode.cloud ? cloudWssUrl : localServerUrl;
    final cleanToken = pairToken.trim().toUpperCase();
    if (cleanToken.isEmpty) {
      return base;
    }
    final separator = base.contains('?') ? '&' : '?';
    return '$base${separator}token=${Uri.encodeComponent(cleanToken)}';
  }

  NetworkConfig copyWith({
    NetworkMode? mode,
    String? cloudWssUrl,
    String? localWsHost,
    int? localWsPort,
    String? pairToken,
  }) {
    return NetworkConfig(
      mode: mode ?? this.mode,
      cloudWssUrl: cloudWssUrl ?? this.cloudWssUrl,
      localWsHost: localWsHost ?? this.localWsHost,
      localWsPort: localWsPort ?? this.localWsPort,
      pairToken: pairToken ?? this.pairToken,
    );
  }

  NetworkConfig withLocalUrl(String rawInput) {
    String candidate = rawInput.trim();
    String? extractedToken;
    NetworkMode? extractedMode;
    if (candidate.startsWith('{')) {
      try {
        final decoded = jsonDecode(candidate) as Map<String, dynamic>;
        if (decoded['wsUrl'] is String) {
          candidate = (decoded['wsUrl'] as String).trim();
          extractedMode = NetworkMode.local;
        }
        if (decoded['mode'] == 'local') {
          extractedMode = NetworkMode.local;
        } else if (decoded['mode'] == 'cloud') {
          extractedMode = NetworkMode.cloud;
        }
        if (decoded['pairToken'] is String) {
          extractedToken = (decoded['pairToken'] as String).trim().toUpperCase();
        }
      } catch (_) {
        // Ignore JSON parse fallback
      }
    }
    try {
      final uri = Uri.parse(candidate.contains('://') ? candidate : 'ws://$candidate');
      final host = uri.host.isNotEmpty ? uri.host : localWsHost;
      final port = uri.hasPort ? uri.port : localWsPort;
      return copyWith(
        mode: extractedMode ?? mode,
        localWsHost: host,
        localWsPort: port,
        pairToken: extractedToken ?? pairToken,
      );
    } catch (_) {
      return this;
    }
  }
}

class NetworkConfigNotifier extends StateNotifier<NetworkConfig> {
  final KeystoreService? _keystore;

  NetworkConfigNotifier({KeystoreService? keystore})
      : _keystore = keystore,
        super(const NetworkConfig()) {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final ks = _keystore;
    if (ks == null) return;
    try {
      final savedMode = await ks.getNetworkMode();
      final savedCloud = await ks.getCustomCloudUrl();
      final savedLocal = await ks.getCustomLocalUrl();
      final savedToken = await ks.getPairToken();

      var next = state;
      if (savedMode == NetworkMode.cloud.name) {
        next = next.copyWith(mode: NetworkMode.cloud);
      } else if (savedMode == NetworkMode.local.name) {
        next = next.copyWith(mode: NetworkMode.local);
      }
      if (savedCloud != null && savedCloud.isNotEmpty) {
        next = next.copyWith(cloudWssUrl: savedCloud);
      }
      if (savedLocal != null && savedLocal.isNotEmpty) {
        next = next.withLocalUrl(savedLocal);
      }
      if (savedToken != null && savedToken.isNotEmpty) {
        next = next.copyWith(pairToken: savedToken.trim().toUpperCase());
      }
      state = next;
    } catch (_) {
      // Ignore storage error during tests
    }
  }

  void setMode(NetworkMode mode) {
    state = state.copyWith(mode: mode);
    _keystore?.saveNetworkMode(mode.name);
  }

  void setCloudflareUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(cloudWssUrl: trimmed);
    _keystore?.saveCustomCloudUrl(trimmed);
  }

  void setLocalUrl(String url) {
    final next = state.withLocalUrl(url);
    state = next;
    _keystore?.saveCustomLocalUrl(next.localServerUrl);
  }

  void setPairToken(String token) {
    final clean = token.trim().toUpperCase();
    state = state.copyWith(pairToken: clean);
    _keystore?.savePairToken(clean);
  }
}

final networkConfigProvider =
    StateNotifierProvider<NetworkConfigNotifier, NetworkConfig>((ref) {
  return NetworkConfigNotifier(keystore: KeystoreService());
});
