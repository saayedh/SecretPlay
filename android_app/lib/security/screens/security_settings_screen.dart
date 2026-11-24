import 'package:flutter/material.dart';
import '../../chat/chat_message.dart';
import '../../cryptography/crypto_service.dart';
import '../../ghost_touch/ghost_touch_theme.dart';
import '../../ghost_touch/models/hologram_models.dart';
import '../../ghost_touch/overlay/floating_hologram_experience.dart';
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
    GhostTouchPreferencesService.instance.load();
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
            _buildGhostTouchSettingsCard(),
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

  Widget _buildGhostTouchSettingsCard() {
    return ValueListenableBuilder<GhostTouchPreferences>(
      valueListenable: GhostTouchPreferencesService.instance.notifier,
      builder: (context, prefs, _) {
        final svc = GhostTouchPreferencesService.instance;
        return Card(
          color: const Color(0xFF151226),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: GhostPalette.neonPink.withOpacity(0.45)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        color: GhostPalette.neonPink, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Ghost Touch Holographic Studio (تنظیمات هولوگرام)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        final demoMsg = EphemeralChatMessage(
                          senderDeviceId: 'preview',
                          text: 'Ghost Touch v2.0 ✨',
                          contentType: ChatContentType.flashCard,
                          cardDataJson: FlashCardData(
                            template: FlashCardTemplate.romanticNeonHeart,
                            text: 'پیش‌نمایش هولوگرام زنده برای تو ✨',
                            stickerId: 'love_glowing_heart',
                            hologramStyle: prefs.defaultStyle,
                            durationSec: prefs.displayDurationSec,
                          ).toJsonString(),
                          hologramStyle: prefs.defaultStyle.name,
                          displayDurationSec: prefs.displayDurationSec,
                          isFlashScreen: true,
                          timestamp: DateTime.now().millisecondsSinceEpoch,
                          isMe: false,
                        );
                        showDialog<void>(
                          context: context,
                          builder: (dCtx) => FloatingHologramExperience(
                            message: demoMsg,
                            isFa: true,
                            hologramStyle: prefs.defaultStyle,
                            cardData: FlashCardData.fromJsonString(demoMsg.cardDataJson),
                            autoVanishSeconds: prefs.displayDurationSec,
                            onDismiss: () => Navigator.of(dCtx).pop(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_circle_fill_rounded,
                          color: GhostPalette.electricCyan, size: 18),
                      label: const Text(
                        'پیش‌نمایش',
                        style: TextStyle(
                            color: GhostPalette.electricCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'سبک پیش‌فرض هولوگرام:',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: HologramStyle.values.map((st) {
                    final active = prefs.defaultStyle == st;
                    return ChoiceChip(
                      avatar: Icon(st.icon, size: 14, color: Colors.white),
                      label: Text(st.label(true), style: const TextStyle(fontSize: 11)),
                      selected: active,
                      selectedColor: GhostPalette.neonPink.withOpacity(0.32),
                      onSelected: (_) => svc.update(prefs.copyWith(defaultStyle: st)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                const Text(
                  'موقعیت نمایش روی صفحه (Overlay Position):',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: OverlayPosition.values.map((pos) {
                    final active = prefs.position == pos;
                    final label = pos == OverlayPosition.top
                        ? 'بالا (Top)'
                        : (pos == OverlayPosition.bottom ? 'پایین (Bottom)' : 'مرکز (Center)');
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Text(label, style: const TextStyle(fontSize: 11)),
                          selected: active,
                          selectedColor: GhostPalette.electricCyan.withOpacity(0.28),
                          onSelected: (_) => svc.update(prefs.copyWith(position: pos)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'مدت نمایش: ${prefs.displayDurationSec}s',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: prefs.displayDurationSec.toDouble().clamp(3.0, 20.0),
                        min: 3,
                        max: 20,
                        divisions: 17,
                        activeColor: GhostPalette.neonGreen,
                        onChanged: (v) =>
                            svc.update(prefs.copyWith(displayDurationSec: v.round())),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      'شدت نور و افکت: ${(prefs.effectIntensity * 100).round()}%',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: prefs.effectIntensity,
                        min: 0.2,
                        max: 1.0,
                        divisions: 8,
                        activeColor: GhostPalette.neonPurple,
                        onChanged: (v) =>
                            svc.update(prefs.copyWith(effectIntensity: v)),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('لرزش اختصاصی هنگام دریافت افکت (Vibrate)'),
                  value: prefs.vibrateEnabled,
                  activeColor: GhostPalette.neonPink,
                  onChanged: (v) => svc.update(prefs.copyWith(vibrateEnabled: v)),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('افکت صوتی ملایم هنگام دریافت هولوگرام (Sound FX)'),
                  value: prefs.soundEnabled,
                  activeColor: GhostPalette.neonGreen,
                  onChanged: (v) => svc.update(prefs.copyWith(soundEnabled: v)),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('حالت کم‌مصرف / کاهش حرکت (Reduced Motion)'),
                  value: prefs.reducedMotion,
                  activeColor: GhostPalette.electricCyan,
                  onChanged: (v) => svc.update(prefs.copyWith(reducedMotion: v)),
                ),
              ],
            ),
          ),
        );
      },
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
