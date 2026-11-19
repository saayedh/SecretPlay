import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/app_localizations.dart';
import '../../cryptography/crypto_service.dart';
import '../../networking/network_mode.dart';
import '../../networking/screens/network_mode_screen.dart';
import '../../networking/screens/qr_scanner_screen.dart';
import '../../security/keystore_service.dart';
import '../../security/screens/security_settings_screen.dart';
import '../../chat/screens/private_chat_screen.dart';
import '../../game/screens/game_home_screen.dart';
import '../../security/auto_lock_service.dart';
import '../contact_model.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final KeystoreService _keystore = KeystoreService();
  final CryptoService _crypto = CryptoService();
  final TextEditingController _searchOrAddIdController = TextEditingController();
  final TextEditingController _aliasController = TextEditingController();

  String _mySecretNumber = '';
  String _myPublicKey = '';
  List<SecretContact> _contacts = [];
  bool _isLoading = true;
  bool _showMyQrCard = false;

  @override
  void initState() {
    super.initState();
    _initMyIdentityAndContacts();
  }

  @override
  void dispose() {
    _searchOrAddIdController.dispose();
    _aliasController.dispose();
    super.dispose();
  }

  Future<void> _initMyIdentityAndContacts() async {
    final deviceId = await _keystore.getOrCreateDeviceId();
    var privKey = await _keystore.getIdentityPrivateKey();
    var pubKey = await _keystore.getIdentityPublicKey();

    if (privKey == null || pubKey == null) {
      final kp = await _crypto.generateIdentityKeyPair();
      privKey = await _crypto.exportPrivateKey(kp);
      pubKey = await _crypto.exportPublicKey(kp);
      await _keystore.saveIdentityKeyPair(
        privateKeyBase64: privKey,
        publicKeyBase64: pubKey,
      );
    }

    var myNumber = await _keystore.getMySecretNumber();
    if (myNumber == null || myNumber.isEmpty) {
      myNumber = SecretContact.deriveMySecretNumber('$deviceId:$pubKey');
      await _keystore.saveMySecretNumber(myNumber);
    }

    final isDecoy = AutoLockService().isDecoyMode;
    final List<SecretContact> loaded = [];

    if (isDecoy) {
      // In Duress / Decoy PIN mode, display harmless arcade tournament bot contacts only!
      loaded.addAll([
        SecretContact(
          contactId: 'SP-100-200',
          alias: 'CyberBot_Support (پشتیبانی بازی)',
          roomToken: 'DECOY-BOT-ROOM-1',
          addedAt: DateTime.now().millisecondsSinceEpoch - 86400000,
          lastActiveAt: DateTime.now().millisecondsSinceEpoch - 3600000,
        ),
        SecretContact(
          contactId: 'SP-808-404',
          alias: 'Tournament_Judge (داور مسابقات)',
          roomToken: 'DECOY-BOT-ROOM-2',
          addedAt: DateTime.now().millisecondsSinceEpoch - 172800000,
          lastActiveAt: DateTime.now().millisecondsSinceEpoch - 7200000,
        ),
      ]);
      if (mounted) {
        setState(() {
          _mySecretNumber = 'SP-000-101';
          _myPublicKey = pubKey!;
          _contacts = loaded;
          _isLoading = false;
        });
      }
      return;
    }

    final rawContacts = await _keystore.getContactsJson();
    if (rawContacts != null && rawContacts.isNotEmpty) {
      try {
        final list = jsonDecode(rawContacts) as List<dynamic>;
        for (final item in list) {
          loaded.add(SecretContact.fromJson(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    // If user previously had a legacy pairToken saved, include it automatically
    final legacyToken = await _keystore.getPairToken();
    if (legacyToken != null &&
        legacyToken.isNotEmpty &&
        !loaded.any((c) => c.roomToken == legacyToken || c.contactId == legacyToken)) {
      final legacyPeerId = await _keystore.getPeerDeviceId();
      final legacyPeerKey = await _keystore.getPeerPublicKey();
      loaded.add(
        SecretContact(
          contactId: legacyToken,
          alias: 'مخاطب قبلی ($legacyToken)',
          roomToken: legacyToken,
          peerDeviceId: legacyPeerId,
          peerPublicKey: legacyPeerKey,
          addedAt: DateTime.now().millisecondsSinceEpoch,
          lastActiveAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _persistContacts(loaded);
    }

    if (mounted) {
      setState(() {
        _mySecretNumber = myNumber!;
        _myPublicKey = pubKey!;
        _contacts = loaded;
        _isLoading = false;
      });
    }
  }

  Future<void> _persistContacts(List<SecretContact> list) async {
    final jsonStr = jsonEncode(list.map((c) => c.toJson()).toList());
    await _keystore.saveContactsJson(jsonStr);
  }

  Future<void> _addOrOpenContact({
    required String rawId,
    String? customAlias,
    String? scannedPeerKey,
    String? scannedRoomToken,
  }) async {
    final normalizedId = SecretContact.normalizeSecretNumber(rawId);
    if (normalizedId.length < 3) return;
    if (normalizedId == _mySecretNumber) {
      final s = S(ref.read(appLocaleProvider));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.tr('این شناسه متعلق به خود شماست! شناسه مخاطب را وارد کنید.', 'That is your own SecretPlay ID!'),
          ),
        ),
      );
      return;
    }

    final roomToken = scannedRoomToken ??
        SecretContact.computePairRoomToken(_mySecretNumber, normalizedId);

    final existingIndex = _contacts.indexWhere(
      (c) => c.contactId == normalizedId || c.roomToken == roomToken,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    SecretContact target;

    if (existingIndex >= 0) {
      final existing = _contacts[existingIndex];
      target = existing.copyWith(
        alias: (customAlias != null && customAlias.trim().isNotEmpty)
            ? customAlias.trim()
            : existing.alias,
        peerPublicKey: scannedPeerKey ?? existing.peerPublicKey,
        lastActiveAt: now,
      );
      _contacts[existingIndex] = target;
    } else {
      target = SecretContact(
        contactId: normalizedId,
        alias: (customAlias != null && customAlias.trim().isNotEmpty)
            ? customAlias.trim()
            : normalizedId,
        roomToken: roomToken,
        peerPublicKey: scannedPeerKey,
        addedAt: now,
        lastActiveAt: now,
      );
      _contacts = [target, ..._contacts];
    }

    await _persistContacts(_contacts);
    _searchOrAddIdController.clear();
    _aliasController.clear();
    setState(() {});

    await _openChatWithContact(target);
  }

  Future<void> _openChatWithContact(SecretContact contact) async {
    await _keystore.savePairToken(contact.roomToken);
    if (contact.peerDeviceId != null && contact.peerPublicKey != null) {
      await _keystore.savePairedPeer(
        peerDeviceId: contact.peerDeviceId!,
        peerPublicKeyBase64: contact.peerPublicKey!,
      );
    }
    ref.read(networkConfigProvider.notifier).setPairToken(contact.roomToken);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrivateChatScreen(activeContact: contact),
      ),
    );
    // Refresh contact list after returning from chat
    await _initMyIdentityAndContacts();
  }

  Future<void> _deleteContact(SecretContact contact) async {
    setState(() {
      _contacts.removeWhere((c) => c.contactId == contact.contactId);
    });
    await _persistContacts(_contacts);
  }

  Future<void> _scanContactQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (scanned == null || scanned.trim().isEmpty) return;

    String contactId = scanned.trim();
    String? alias;
    String? pubKey;
    String? explicitRoom;

    if (contactId.startsWith('{')) {
      try {
        final map = jsonDecode(contactId) as Map<String, dynamic>;
        if (map['secretNumber'] is String) {
          contactId = map['secretNumber'] as String;
        } else if (map['pairToken'] is String) {
          contactId = map['pairToken'] as String;
          explicitRoom = map['pairToken'] as String;
        }
        if (map['alias'] is String) alias = map['alias'] as String;
        if (map['publicKey'] is String) pubKey = map['publicKey'] as String;
        if (map['wsUrl'] is String) {
          final url = map['wsUrl'] as String;
          if (url.startsWith('ws://')) {
            ref.read(networkConfigProvider.notifier).setMode(NetworkMode.local);
            ref.read(networkConfigProvider.notifier).setLocalUrl(url.split('?').first);
          } else if (url.startsWith('wss://')) {
            ref.read(networkConfigProvider.notifier).setMode(NetworkMode.cloud);
            ref.read(networkConfigProvider.notifier).setCloudflareUrl(url.split('?').first);
          }
        }
      } catch (_) {}
    }

    await _addOrOpenContact(
      rawId: contactId,
      customAlias: alias,
      scannedPeerKey: pubKey,
      scannedRoomToken: explicitRoom,
    );
  }

  void _showAddContactModal(S s) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: s.dir,
        child: AlertDialog(
          backgroundColor: const Color(0xFF16161D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF64D2FF)),
          ),
          title: Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF00FFA3)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.tr('افزودن یا جستجوی مخاطب با شناسه', 'Add / Find Contact by ID'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _searchOrAddIdController,
                style: const TextStyle(
                  color: Color(0xFF00FFA3),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  labelText: s.tr('شناسه اختصاصی مخاطب (مثل شماره تلفن)', 'Partner SecretPlay ID'),
                  hintText: 'SP-742-918',
                  labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF1E1E26),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _aliasController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: s.tr('نام دلخواه مخاطب (اختیاری)', 'Contact Nickname (Optional)'),
                  hintText: s.tr('مثلاً: علی، سارا، دوست صمیمی...', 'e.g. Alex, Partner...'),
                  labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF1E1E26),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(s.tr('انصراف', 'Cancel')),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
              label: Text(
                s.tr('افزودن و شروع گفتگو', 'Add & Open Chat'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FFA3),
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                final raw = _searchOrAddIdController.text.trim();
                final alias = _aliasController.text.trim();
                Navigator.of(ctx).pop();
                if (raw.isNotEmpty) {
                  _addOrOpenContact(rawId: raw, customAlias: alias);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLocaleProvider);
    final s = S(lang);
    final netConfig = ref.watch(networkConfigProvider);

    final myQrPayload = jsonEncode({
      'secretNumber': _mySecretNumber,
      'publicKey': _myPublicKey,
      'wsUrl': netConfig.mode == NetworkMode.cloud
          ? netConfig.cloudflareUrl
          : netConfig.localServerUrl,
    });

    final query = _searchOrAddIdController.text.trim().toUpperCase();
    final filteredContacts = query.isEmpty
        ? _contacts
        : _contacts
            .where((c) =>
                c.contactId.contains(query) ||
                c.alias.toUpperCase().contains(query) ||
                c.roomToken.contains(query))
            .toList();

    return Directionality(
      textDirection: s.dir,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.lock_rounded, color: Color(0xFFFF453A)),
            tooltip: s.tr('قفل فوری و بازگشت به بازی', 'Lock & Return to Game'),
            onPressed: () {
              AutoLockService().triggerLock('manual_exit');
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const GameHomeScreen()),
                (route) => false,
              );
            },
          ),
          title: Text(
            s.tr('مخاطبین و شناسه من', 'Contacts & My Secret ID'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.amber),
              tooltip: s.tr('اسکن QR مخاطب', 'Scan Partner QR'),
              onPressed: _scanContactQr,
            ),
            IconButton(
              icon: const Icon(Icons.router_rounded, color: Color(0xFF64D2FF)),
              tooltip: s.tr('تنظیمات شبکه', 'Network Mode'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NetworkModeScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.security_rounded, color: Colors.white70),
              tooltip: s.tr('تنظیمات امنیتی', 'Security Settings'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
                );
              },
            ),
            TextButton(
              onPressed: () => ref.read(appLocaleProvider.notifier).toggleLanguage(),
              child: Text(
                s.isFa ? 'EN' : 'فا',
                style: const TextStyle(
                  color: Color(0xFFFFD60A),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF00FFA3),
          foregroundColor: Colors.black,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text(
            s.tr('پیام به شناسه جدید', 'Message New ID'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: () => _showAddContactModal(s),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // My Unique Phone-like SecretPlay ID Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF141E30), Color(0xFF243B55)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.55)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00FFA3).withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.badge_rounded,
                                  color: Color(0xFF00FFA3),
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.tr(
                                        'شناسه اختصاصی شما (شماره SecretPlay)',
                                        'Your Personal SecretPlay Number',
                                      ),
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                    const SizedBox(height: 3),
                                    SelectableText(
                                      _mySecretNumber,
                                      style: const TextStyle(
                                        color: Color(0xFF00FFA3),
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.5,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, color: Colors.white),
                                tooltip: s.tr('کپی شناسه من', 'Copy My ID'),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _mySecretNumber));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        s.tr(
                                          'شناسه $_mySecretNumber کپی شد! برای دوستتان بفرستید.',
                                          'ID $_mySecretNumber copied!',
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: Icon(
                                  _showMyQrCard ? Icons.expand_less : Icons.qr_code_2_rounded,
                                  color: const Color(0xFF64D2FF),
                                  size: 28,
                                ),
                                tooltip: s.tr('نمایش QR اختصاصی من', 'Show My QR Card'),
                                onPressed: () => setState(() => _showMyQrCard = !_showMyQrCard),
                              ),
                            ],
                          ),
                          if (_showMyQrCard) ...[
                            const Divider(color: Colors.white24, height: 24),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: QrImageView(
                                data: myQrPayload,
                                version: QrVersions.auto,
                                size: 170,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              s.tr(
                                'دوست شما با اسکن این QR مستقیماً شما را به مخاطبینش اضافه می‌کند',
                                'Partner can scan this QR to add your ID & public key instantly',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Instant Direct ID Input / Search Bar
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchOrAddIdController,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (val) {
                              if (val.trim().isNotEmpty) {
                                _addOrOpenContact(rawId: val);
                              }
                            },
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.dialpad_rounded, color: Color(0xFF64D2FF)),
                              hintText: s.tr(
                                'شناسه مخاطب را وارد کنید (مثلاً SP-742-918)...',
                                'Enter partner ID (e.g. SP-742-918) to chat...',
                              ),
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                              filled: true,
                              fillColor: const Color(0xFF181820),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007AFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () {
                            final raw = _searchOrAddIdController.text.trim();
                            if (raw.isNotEmpty) {
                              _addOrOpenContact(rawId: raw);
                            } else {
                              _showAddContactModal(s);
                            }
                          },
                          child: Text(
                            s.tr('ورود به چت', 'Start Chat'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Contacts List Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          s.tr(
                            'مخاطبین خصوصی شما (${filteredContacts.length})',
                            'Your Private Contacts (${filteredContacts.length})',
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          s.tr('پشتیبانی از ارسال پیام آفلاین ✓', 'Offline Queuing Enabled ✓'),
                          style: const TextStyle(color: Color(0xFF00FFA3), fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (filteredContacts.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14141A),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.people_outline_rounded,
                              color: Colors.white24,
                              size: 54,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              s.tr(
                                'هنوز مخاطبی اضافه نکرده‌اید.\nشناسه دوستتان (مثلاً SP-742-918) را در کادر بالا وارد کنید یا QR او را اسکن کنید تا گفتگو شروع شود!',
                                'No contacts yet.\nEnter your partner\'s SecretPlay ID above or scan their QR code to start chatting!',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else
                      ...filteredContacts.map((contact) {
                        final hasKey =
                            contact.peerPublicKey != null && contact.peerPublicKey!.isNotEmpty;
                        return Card(
                          color: const Color(0xFF16161E),
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: hasKey
                                  ? const Color(0xFF00FFA3).withOpacity(0.35)
                                  : Colors.white12,
                            ),
                          ),
                          child: ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF007AFF).withOpacity(0.2),
                              child: const Icon(Icons.person_rounded, color: Color(0xFF64D2FF)),
                            ),
                            title: Text(
                              contact.alias,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 3),
                                Text(
                                  s.tr(
                                    'شناسه: ${contact.contactId}',
                                    'ID: ${contact.contactId}',
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFF00FFA3),
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  hasKey
                                      ? s.tr(
                                          '🔐 کلید رمزنگاری تایید شده • ارسال آنلاین و آفلاین فعال',
                                          '🔐 E2EE Key Pinned • Online & Offline Messaging Ready',
                                        )
                                      : s.tr(
                                          '⏳ آماده تبادل خودکار کلید در اولین اتصال',
                                          '⏳ Ready for automatic E2EE key exchange',
                                        ),
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.white38,
                                    size: 20,
                                  ),
                                  onPressed: () => _deleteContact(contact),
                                ),
                                const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: Color(0xFF00FFA3),
                                ),
                              ],
                            ),
                            onTap: () => _openChatWithContact(contact),
                          ),
                        );
                      }),
                  ],
                ),
              ),
      ),
    );
  }
}
