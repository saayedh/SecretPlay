import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../networking/network_mode.dart';
import '../../networking/websocket_client.dart';
import 'connection_status_screen.dart';
import 'qr_scanner_screen.dart';

export '../../networking/network_mode.dart' show networkConfigProvider, NetworkConfigNotifier;

class NetworkModeScreen extends ConsumerStatefulWidget {
  final SecretPlayWebSocketClient? wsClient;

  const NetworkModeScreen({super.key, this.wsClient});

  @override
  ConsumerState<NetworkModeScreen> createState() => _NetworkModeScreenState();
}

class _NetworkModeScreenState extends ConsumerState<NetworkModeScreen> {
  late TextEditingController _cloudflareController;
  late TextEditingController _localController;

  static const Color _cyberCyan = Color(0xFF64D2FF);
  static const Color _privateBg = Color(0xFF000000);
  static const Color _privateSurface = Color(0xFF1C1C1E);

  @override
  void initState() {
    super.initState();
    final config = ref.read(networkConfigProvider);
    _cloudflareController = TextEditingController(text: config.cloudflareUrl);
    _localController = TextEditingController(text: config.localServerUrl);
  }

  @override
  void dispose() {
    _cloudflareController.dispose();
    _localController.dispose();
    super.dispose();
  }

  Future<void> _scanServerQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result != null && result.isNotEmpty && mounted) {
      ref.read(networkConfigProvider.notifier).setLocalUrl(result);
      final updated = ref.read(networkConfigProvider);
      setState(() {
        _localController.text = updated.localServerUrl;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(networkConfigProvider);
    final notifier = ref.read(networkConfigProvider.notifier);

    return Theme(
      data: AppThemes.privateTheme,
      child: Scaffold(
        backgroundColor: _privateBg,
        appBar: AppBar(
          backgroundColor: _privateSurface,
          title: const Text(
            'NETWORK ARCHITECTURE',
            style: TextStyle(color: _cyberCyan, fontFamily: 'monospace', fontSize: 16),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: _cyberCyan),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            if (widget.wsClient != null)
              IconButton(
                icon: const Icon(Icons.analytics_outlined, color: _cyberCyan),
                tooltip: 'Connection Telemetry',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConnectionStatusScreen(wsClient: widget.wsClient!),
                    ),
                  );
                },
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildModeCard(
                context,
                mode: NetworkMode.cloud,
                selectedMode: config.mode,
                icon: Icons.cloud_outlined,
                title: 'Mode A: Cloudflare Cloud Mode',
                subtitle: 'Cloudflare Workers + Durable Objects relay\nRequires global Internet connection',
                onTap: () => notifier.setMode(NetworkMode.cloud),
              ),
              const SizedBox(height: 16),
              _buildModeCard(
                context,
                mode: NetworkMode.local,
                selectedMode: config.mode,
                icon: Icons.wifi_tethering_rounded,
                title: 'Mode B: Local / Offline Mode',
                subtitle: 'Windows Laptop server on Hotspot or LAN\nWorks with zero Internet connectivity',
                onTap: () => notifier.setMode(NetworkMode.local),
              ),
              const SizedBox(height: 32),
              if (config.mode == NetworkMode.cloud) ...[
                _buildServerConfig(
                  label: 'CLOUDFLARE WORKER WSS ENDPOINT',
                  controller: _cloudflareController,
                  hint: 'wss://secretplay-relay.workers.dev/ws',
                  onChanged: notifier.setCloudflareUrl,
                ),
              ] else ...[
                _buildServerConfig(
                  label: 'LOCAL LAPTOP SERVER WS ENDPOINT',
                  controller: _localController,
                  hint: 'ws://192.168.137.1:8787/ws',
                  onChanged: notifier.setLocalUrl,
                ),
                const SizedBox(height: 16),
                _buildQrScanButton(),
              ],
              const SizedBox(height: 32),
              _buildInfoBox(config),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context, {
    required NetworkMode mode,
    required NetworkMode selectedMode,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isSelected = mode == selectedMode;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? _cyberCyan.withOpacity(0.1) : _privateSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _cyberCyan : Colors.grey.shade800,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? _cyberCyan.withOpacity(0.2) : Colors.grey.shade800,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? _cyberCyan : Colors.grey,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? _cyberCyan : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: _cyberCyan),
          ],
        ),
      ),
    );
  }

  Widget _buildServerConfig({
    required String label,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            filled: true,
            fillColor: _privateSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.grey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _cyberCyan),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQrScanButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _scanServerQr,
        icon: const Icon(Icons.qr_code_scanner, color: _cyberCyan),
        label: const Text(
          'SCAN LAPTOP TERMINAL QR CODE',
          style: TextStyle(color: _cyberCyan, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _cyberCyan),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBox(NetworkConfig config) {
    final isCloud = config.mode == NetworkMode.cloud;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _privateSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: isCloud ? Colors.blue.shade300 : const Color(0xFF00FFA3),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isCloud ? 'Cloud Mode Active' : 'Local Offline Mode Active',
                style: TextStyle(
                  color: isCloud ? Colors.blue.shade300 : const Color(0xFF00FFA3),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isCloud
                ? 'Active Endpoint: ${config.activeWsUrl}\n'
                    'Ciphertext frames are relayed through Cloudflare Durable Objects with WebSocket Hibernation. Zero messages are stored.'
                : 'Active Endpoint: ${config.activeWsUrl}\n'
                    'Ciphertext frames are relayed through your laptop over LAN/Hotspot. WebRTC voice flows direct phone-to-phone with zero Internet.',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
