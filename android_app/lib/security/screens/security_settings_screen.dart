import 'package:flutter/material.dart';
import '../../cryptography/crypto_service.dart';
import '../../security/keystore_service.dart';
import '../../security/auto_lock_service.dart';
import '../../recovery/screens/recovery_screen.dart';
import '../../game/screens/game_home_screen.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final KeystoreService _keystore = KeystoreService();
  final CryptoService _crypto = CryptoService();
  String? _deviceId;
  String? _myPubKey;
  String? _peerId;
  String? _peerPubKey;
  bool _biometricsEnabled = true;
  bool _hasDuressPin = false;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final devId = await _keystore.getOrCreateDeviceId();
    final pubKey = await _keystore.getIdentityPublicKey();
    final pId = await _keystore.getPeerDeviceId();
    final pKey = await _keystore.getPeerPublicKey();
    final duressHash = await _keystore.getDuressPinHash();

    if (mounted) {
      setState(() {
        _deviceId = devId;
        _myPubKey = pubKey;
        _peerId = pId;
        _peerPubKey = pKey;
        _hasDuressPin = duressHash != null && duressHash.isNotEmpty;
      });
    }
  }

  Future<void> _configureDuressPinDialog() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'تنظیم پین فریبنده / حالت تهدید (Duress PIN)',
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'یک پین ۴ رقمی متفاوت از پین اصلی وارد کنید (مثلاً 9999).\nاگر تحت فشار این پین را وارد کنید، برنامه یک محیط چت و مخاطبین بی‌خطر آزمایشی نشان می‌دهد!',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 4,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFD60A),
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
              ),
              decoration: InputDecoration(
                hintText: '9999',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF121216),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('انصراف / Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD60A),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('ذخیره پین فریبنده'),
          ),
        ],
      ),
    );
    if (pin != null && pin.length == 4) {
      final hash = await _crypto.hashPassphrase(pin);
      await _keystore.saveDuressPinHash(hash);
      if (mounted) {
        setState(() => _hasDuressPin = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('پین فریبنده (Duress PIN) با موفقیت فعال شد!')),
        );
      }
    }
  }

  void _revokePeer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Revoke Paired Device?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently disconnect and unpair the second device slot. Re-pairing will require physical QR verification.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF453A)),
            child: const Text('REVOKE'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _keystore.revokePairing();
      AutoLockService().triggerLock('peer_revoked');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GameHomeScreen()),
        (route) => false,
      );
    }
  }

  void _emergencyWipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('EMERGENCY FULL WIPE?', style: TextStyle(color: Color(0xFFFF453A))),
        content: const Text(
          'This will permanently delete all cryptographic identity keys, pairings, and passphrase hashes from Android Keystore. This action is irreversible.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF453A)),
            child: const Text('ERASE EVERYTHING'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _keystore.fullWipe();
      AutoLockService().triggerLock('emergency_wipe');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GameHomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('SECURITY & IDENTITY'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'DEVICE IDENTITIES',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 12),
            _buildKeyCard('This Device ID', _deviceId ?? 'Generating...', Icons.smartphone),
            const SizedBox(height: 8),
            _buildKeyCard(
              'Ed25519 Identity Public Key',
              _myPubKey ?? 'None',
              Icons.key,
            ),
            const SizedBox(height: 8),
            _buildKeyCard('Paired Peer ID', _peerId ?? 'Unpaired', Icons.person_outline),
            const SizedBox(height: 8),
            _buildKeyCard('Paired Peer Public Key', _peerPubKey ?? 'Unpaired', Icons.vpn_key_outlined),
            const SizedBox(height: 24),

            const Text(
              'AUTHENTICATION & HARDENING',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF1C1C1E),
              child: SwitchListTile(
                secondary: const Icon(Icons.fingerprint, color: Color(0xFF64D2FF)),
                title: const Text('BiometricPrompt Unlock / ورود با اثر انگشت'),
                value: _biometricsEnabled,
                onChanged: (val) => setState(() => _biometricsEnabled = val),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1C1C1E),
              child: SwitchListTile(
                secondary: const Icon(Icons.bolt_rounded, color: Color(0xFFFF007A)),
                title: const Text('Receive Lock-Screen Flash Holograms (دریافت فلش روی صفحه قفل)'),
                subtitle: const Text(
                  'Keep encrypted relay active in background so partner sketches/notes pop up on your locked screen',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                value: !AutoLockService().strictBackgroundAutoLock,
                onChanged: (val) {
                  setState(() {
                    AutoLockService().setStrictBackgroundAutoLock(!val);
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1C1C1E),
              child: SwitchListTile(
                secondary: const Icon(Icons.vibration_rounded, color: Color(0xFF00FFA3)),
                title: const Text('Shake-to-Lock Panic Escape (قفل فوری با تکان دادن گوشی یا کلید Esc)'),
                subtitle: const Text(
                  'Shake phone or press Esc to instantly wipe RAM and jump back to the puzzle game',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                value: AutoLockService().shakeToLockEnabled,
                onChanged: (val) {
                  setState(() {
                    AutoLockService().setShakeToLockEnabled(val);
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1C1C1E),
              child: ListTile(
                leading: const Icon(Icons.theater_comedy_rounded, color: Color(0xFFFFD60A)),
                title: Text(
                  _hasDuressPin
                      ? 'Duress / Decoy PIN: ACTIVE (پین فریبنده فعال است ✓)'
                      : 'Configure Duress / Decoy PIN (تنظیم پین فریبنده ۴ رقمی)',
                ),
                subtitle: const Text(
                  'Unlocks into a harmless decoy contact list if you are forced to enter your PIN',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                trailing: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFFFFD60A)),
                onTap: _configureDuressPinDialog,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFF1C1C1E),
              child: ListTile(
                leading: const Icon(Icons.restore, color: Color(0xFF00FFA3)),
                title: const Text('Encrypted Account Recovery'),
                subtitle: const Text('Export/Import offline identity backup vault', style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white54),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecoveryScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'REVOCATION & DESTRUCTION',
              style: TextStyle(color: Color(0xFFFF453A), fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.link_off),
              label: const Text('REVOKE PAIRED PEER'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C2C2E),
                foregroundColor: const Color(0xFFFF9500),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _peerId != null ? _revokePeer : null,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever),
              label: const Text('EMERGENCY CRYPTOGRAPHIC WIPE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF453A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _emergencyWipe,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF64D2FF), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
