import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/app_localizations.dart';
import '../../core/relay_directory_service.dart';
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

    await RelayDirectoryService.registerIdentity(
      deviceId: deviceId,
      secretNumber: myNumber,
      publicKeyBase64: pubKey,
    );

    if (mounted) {
      final isFa = ref.read(appLocaleProvider) == AppLang.fa;
      RelayDirectoryService.checkAndPromptUpdate(context, isFa: isFa);
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
            s.tr('این شناسه متعلق به خود شماست!', 'That is your own SecretPlay ID!'),
          ),
        ),
      );
      return;
    }

    final roomToken = scannedRoomToken ??
        SecretContact.computePairRoomToken(_mySecretNumber, normalizedId);

    String? resolvedPeerDeviceId;
    String? resolvedPeerPublicKey = scannedPeerKey;
    if (resolvedPeerPublicKey == null) {
      final found = await RelayDirectoryService.lookupBySecretNumber(normalizedId);
      if (found != null) {
        resolvedPeerDeviceId = found['deviceId'];
        resolvedPeerPublicKey = found['publicKey'];
      }
    }

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
        peerDeviceId: resolvedPeerDeviceId ?? existing.peerDeviceId,
        peerPublicKey: resolvedPeerPublicKey ?? existing.peerPublicKey,
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
        peerDeviceId: resolvedPeerDeviceId,
        peerPublicKey: resolvedPeerPublicKey,
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
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => PrivateChatScreen(activeContact: contact),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
      ),
    );
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

  void _showMyQrPassModal(S s, String myQrPayload) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: s.dir,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF131624),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Color(0xFF00FFA3), width: 1.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.tr('کارت دیجیتال و شناسه SecretPlay شما', 'Your SecretPlay Digital Pass'),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FFA3).withOpacity(0.35),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: myQrPayload,
                  version: QrVersions.auto,
                  size: 185,
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                _mySecretNumber,
                style: const TextStyle(
                  color: Color(0xFF00FFA3),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.tr(
                  'دوستتان با اسکن این کد یا زدن این شماره مستقیم با شما رمزنگاری می‌شود',
                  'Share this ID or let your partner scan this QR to connect instantly',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddContactModal(S s) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: s.dir,
        child: AlertDialog(
          backgroundColor: const Color(0xFF131624),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFF00E5FF)),
          ),
          title: Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF00FFA3)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.tr('افزودن مخاطب با شناسه', 'Add Contact by ID'),
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
                  labelText: s.tr('شناسه اختصاصی مخاطب', 'Partner SecretPlay ID'),
                  hintText: 'SP-742-918',
                  labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF0B0D16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _aliasController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: s.tr('نام دلخواه مخاطب (اختیاری)', 'Nickname (Optional)'),
                  hintText: s.tr('مثلاً: علی، سارا...', 'e.g. Alex, Partner...'),
                  labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0B0D16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
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
              label: Text(s.tr('شروع گفتگو', 'Start Chat')),
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

  List<Color> _avatarGradientFor(String id) {
    final hash = id.codeUnits.fold<int>(0, (a, b) => a + b);
    const palettes = [
      [Color(0xFF00FFA3), Color(0xFF00B8D4)],
      [Color(0xFFFF007A), Color(0xFF7928CA)],
      [Color(0xFF00E5FF), Color(0xFF2979FF)],
      [Color(0xFFFFB800), Color(0xFFFF3D00)],
      [Color(0xFFBF5AF2), Color(0xFF5E5CE6)],
    ];
    return palettes[hash % palettes.length];
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
        backgroundColor: const Color(0xFF07080D),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0F18),
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
            s.tr('SecretPlay • پیام‌رسان امن', 'SecretPlay • Secure Vault'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFFFB800)),
              tooltip: s.tr('اسکن QR مخاطب', 'Scan QR'),
              onPressed: _scanContactQr,
            ),
            IconButton(
              icon: const Icon(Icons.system_update_rounded, color: Color(0xFF00FFA3)),
              tooltip: s.tr('بررسی آپدیت جدید', 'Updates'),
              onPressed: () => RelayDirectoryService.checkAndPromptUpdate(
                context,
                isFa: s.isFa,
                manualCheck: true,
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
              color: const Color(0xFF171A26),
              onSelected: (v) {
                if (v == 'lang') {
                  ref.read(appLocaleProvider.notifier).toggleLanguage();
                } else if (v == 'net') {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NetworkModeScreen()),
                  );
                } else if (v == 'sec') {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'lang',
                  child: Text(
                    s.isFa ? '🌐 Switch to English' : '🌐 تغییر زبان به فارسی',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                PopupMenuItem(
                  value: 'net',
                  child: Text(
                    s.tr('📡 حالت شبکه (کلودفلر / لوکال)', '📡 Network Mode'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                PopupMenuItem(
                  value: 'sec',
                  child: Text(
                    s.tr('🛡️ تنظیمات امنیتی و پین فریبنده', '🛡️ Security & Duress PIN'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF00FFA3),
          foregroundColor: Colors.black,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text(
            s.tr('مخاطب جدید', 'New Chat'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          onPressed: () => _showAddContactModal(s),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Column(
                  children: [
                    // Sleek My Secret ID Pill Banner
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF141B30), Color(0xFF1C2847)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF00FFA3).withOpacity(0.15),
                              ),
                              child: const Icon(Icons.fingerprint_rounded, color: Color(0xFF00FFA3)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.tr('شناسه اختصاصی شما', 'Your SecretPlay ID'),
                                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                                  ),
                                  SelectableText(
                                    _mySecretNumber,
                                    style: const TextStyle(
                                      color: Color(0xFF00FFA3),
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'monospace',
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _mySecretNumber));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(s.tr('شناسه $_mySecretNumber کپی شد!', 'Copied!')),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.qr_code_2_rounded,
                                color: Color(0xFF00E5FF),
                                size: 26,
                              ),
                              onPressed: () => _showMyQrPassModal(s, myQrPayload),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Direct Dial / Search Input
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
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
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00E5FF)),
                                hintText: s.tr(
                                  'شماره SecretPlay مخاطب را بزنید (مثلاً SP-742-918)...',
                                  'Enter ID (e.g. SP-742-918) or search...',
                                ),
                                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                                filled: true,
                                fillColor: const Color(0xFF131624),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          if (_searchOrAddIdController.text.trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E5FF),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => _addOrOpenContact(rawId: _searchOrAddIdController.text),
                              child: Text(s.tr('چت', 'Go')),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Contacts List
                    Expanded(
                      child: filteredContacts.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.forum_outlined,
                                      color: Colors.white.withOpacity(0.14),
                                      size: 64,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      s.tr(
                                        'هنوز گفتگویی ندارید.\nشماره SecretPlay دوستتان را بالا وارد کنید یا دکمه «مخاطب جدید» را بزنید.',
                                        'No chats yet.\nEnter your partner\'s SecretPlay ID above or tap New Chat.',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 84),
                              itemCount: filteredContacts.length,
                              itemBuilder: (context, index) {
                                final contact = filteredContacts[index];
                                final grad = _avatarGradientFor(contact.contactId);
                                final initial = contact.alias.isNotEmpty
                                    ? contact.alias.characters.first.toUpperCase()
                                    : 'S';
                                final hasKey = contact.peerPublicKey != null &&
                                    contact.peerPublicKey!.isNotEmpty;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF131624),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: hasKey
                                          ? const Color(0xFF00FFA3).withOpacity(0.28)
                                          : Colors.white.withOpacity(0.07),
                                    ),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => _openChatWithContact(contact),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(colors: grad),
                                            ),
                                            child: Center(
                                              child: Text(
                                                initial,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  contact.alias,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Row(
                                                  children: [
                                                    Text(
                                                      contact.contactId,
                                                      style: const TextStyle(
                                                        color: Color(0xFF00E5FF),
                                                        fontSize: 12,
                                                        fontFamily: 'monospace',
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Icon(
                                                      hasKey
                                                          ? Icons.verified_user_rounded
                                                          : Icons.hourglass_bottom_rounded,
                                                      size: 13,
                                                      color: hasKey
                                                          ? const Color(0xFF00FFA3)
                                                          : Colors.amber,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              color: Colors.white30,
                                              size: 20,
                                            ),
                                            onPressed: () => _deleteContact(contact),
                                          ),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: Color(0xFF00FFA3),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
