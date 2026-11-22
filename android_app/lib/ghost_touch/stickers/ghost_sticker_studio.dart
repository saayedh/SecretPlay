import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/widgets/cyber_sticker_sheet.dart';
import '../drawing/ultimate_drawing_studio.dart';
import '../ghost_touch_theme.dart';
import '../models/hologram_models.dart';
import 'ghost_sticker_catalog.dart';
import 'ghost_sticker_painter.dart';

/// Advanced Holographic Sticker Studio (Phase 2).
///
/// Features:
/// - 66 original animated vector stickers across 6 themed categories
/// - Favorites, Recent, and Custom Signature Stickers tabs
/// - Single shared [AnimationController] driving all grid tiles at 60 FPS
/// - Live Large Animated Preview Header with Favorite toggle & Surprise Me
/// - Hologram reveal style & duration selector + Lock/Floating Flash toggle
class GhostStickerStudio extends StatefulWidget {
  final bool isFa;
  final bool initialFlashOnScreen;
  final Future<SignatureSticker?> Function(BuildContext context)?
      onCreateSignature;

  const GhostStickerStudio({
    super.key,
    required this.isFa,
    this.initialFlashOnScreen = false,
    this.onCreateSignature,
  });

  static Future<CyberStickerSelection?> show(
    BuildContext context, {
    required bool isFa,
    bool initialFlashOnScreen = false,
    Future<SignatureSticker?> Function(BuildContext context)? onCreateSignature,
  }) {
    return showModalBottomSheet<CyberStickerSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GhostStickerStudio(
        isFa: isFa,
        initialFlashOnScreen: initialFlashOnScreen,
        onCreateSignature: onCreateSignature,
      ),
    );
  }

  @override
  State<GhostStickerStudio> createState() => _GhostStickerStudioState();
}

class _GhostStickerStudioState extends State<GhostStickerStudio>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sharedAnim;
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<String, Uint8List> _sigBytesCache = {};
  final math.Random _rng = math.Random();

  String _activeTab = 'all';
  String _searchQuery = '';
  late GhostStickerDef _selectedSticker;
  SignatureSticker? _selectedSignature;
  late bool _flashOnScreen;
  late HologramStyle _hologramStyle;
  late int _durationSec;

  static const List<int> _durationPresets = [5, 7, 10, 15, 20];

  @override
  void initState() {
    super.initState();
    final prefs = GhostTouchPreferencesService.instance.current;
    _flashOnScreen = widget.initialFlashOnScreen;
    _hologramStyle = prefs.defaultStyle;
    _durationSec = prefs.displayDurationSec;
    _selectedSticker = GhostStickerCatalog.all.first;
    _sharedAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    GhostTouchPreferencesService.instance.load();
  }

  @override
  void dispose() {
    _sharedAnim.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Uint8List? _decodeSignature(SignatureSticker sig) {
    final existing = _sigBytesCache[sig.id];
    if (existing != null) return existing;
    try {
      final bytes = base64Decode(sig.pngBase64);
      _sigBytesCache[sig.id] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _cycleHologramStyle() {
    HapticFeedback.selectionClick();
    const values = HologramStyle.values;
    final nextIdx = (values.indexOf(_hologramStyle) + 1) % values.length;
    setState(() => _hologramStyle = values[nextIdx]);
  }

  void _cycleDuration() {
    HapticFeedback.selectionClick();
    final idx = _durationPresets.indexOf(_durationSec);
    final nextIdx = idx < 0 ? 1 : (idx + 1) % _durationPresets.length;
    setState(() => _durationSec = _durationPresets[nextIdx]);
  }

  void _pickSurprise() {
    HapticFeedback.mediumImpact();
    const all = GhostStickerCatalog.all;
    final chosen = all[_rng.nextInt(all.length)];
    const styles = HologramStyle.values;
    setState(() {
      _selectedSignature = null;
      _selectedSticker = chosen;
      _hologramStyle = styles[_rng.nextInt(styles.length)];
      _flashOnScreen = true;
    });
  }

  Future<void> _handleCreateSignature() async {
    SignatureSticker? created;
    if (widget.onCreateSignature != null) {
      created = await widget.onCreateSignature!(context);
    } else {
      final sketch = await UltimateDrawingStudio.open(
        context,
        isFa: widget.isFa,
        signatureMode: true,
      );
      if (sketch != null) {
        created = SignatureSticker(
          id: 'sig_${DateTime.now().millisecondsSinceEpoch}',
          name: sketch.caption.trim().isEmpty
              ? (widget.isFa ? 'امضای من' : 'My Signature')
              : sketch.caption.trim(),
          pngBase64: sketch.pngBase64,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }
    if (created != null && mounted) {
      await GhostTouchPreferencesService.instance.addSignatureSticker(created);
      setState(() {
        _activeTab = 'signature';
        _selectedSignature = created;
      });
    }
  }

  Future<void> _sendSelected() async {
    HapticFeedback.lightImpact();
    if (_selectedSignature != null) {
      final sig = _selectedSignature!;
      Navigator.pop(
        context,
        CyberStickerSelection(
          sticker: CyberSticker(
            id: 'sig_${sig.id}',
            emoji: '✍️',
            titleFa: sig.name,
            titleEn: sig.name,
            category: 'signature',
            neonColor: GhostPalette.electricCyan,
          ),
          flashOnScreen: _flashOnScreen,
          hologramStyle: _hologramStyle,
          durationSec: _durationSec,
          signaturePngBase64: sig.pngBase64,
          signatureName: sig.name,
        ),
      );
      return;
    }

    await GhostTouchPreferencesService.instance
        .recordRecentSticker(_selectedSticker.id);
    if (!mounted) return;
    Navigator.pop(
      context,
      CyberStickerSelection(
        sticker: CyberSticker.fromGhostDef(_selectedSticker),
        flashOnScreen: _flashOnScreen,
        hologramStyle: _hologramStyle,
        durationSec: _durationSec,
      ),
    );
  }

  List<GhostStickerDef> _filteredStickers(GhostTouchPreferences prefs) {
    Iterable<GhostStickerDef> base;
    if (_activeTab == 'all') {
      base = GhostStickerCatalog.all;
    } else if (_activeTab == 'favorites') {
      base = prefs.favoriteStickerIds
          .map(GhostStickerCatalog.findById)
          .toList();
    } else if (_activeTab == 'recent') {
      base = prefs.recentStickerIds
          .map(GhostStickerCatalog.findById)
          .toList();
    } else if (_activeTab == 'signature') {
      base = const [];
    } else {
      final cat = GhostStickerCategory.values.firstWhere(
        (c) => c.name == _activeTab,
        orElse: () => GhostStickerCategory.love,
      );
      base = GhostStickerCatalog.byCategory(cat);
    }

    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return base.toList();
    return base.where((s) {
      return s.titleEn.toLowerCase().contains(q) ||
          s.titleFa.toLowerCase().contains(q) ||
          s.category.name.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isFa = widget.isFa;
    final screenH = MediaQuery.of(context).size.height;

    return Directionality(
      textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
      child: ValueListenableBuilder<GhostTouchPreferences>(
        valueListenable: GhostTouchPreferencesService.instance.notifier,
        builder: (context, prefs, _) {
          final isSignatureTab = _activeTab == 'signature';
          final items = _filteredStickers(prefs);
          final isFav = prefs.favoriteStickerIds.contains(_selectedSticker.id);
          final accent = _selectedSignature != null
              ? GhostPalette.electricCyan
              : _selectedSticker.primaryColor;

          return Container(
            height: screenH * 0.84,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF17122B), GhostPalette.deepSpace],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: accent.withOpacity(0.85),
                  width: 1.6,
                ),
              ),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  width: 46,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),

                // Top Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isFa
                                  ? 'استودیو استیکر هولوگرافیک'
                                  : 'Holographic Sticker Studio',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              isFa
                                  ? '${GhostStickerCatalog.all.length} طرح وکتور زنده • انتخاب و پیش‌نمایش'
                                  : '${GhostStickerCatalog.all.length} animated vector artworks',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.58),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Surprise Me button
                      InkWell(
                        onTap: _pickSurprise,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                GhostPalette.neonPurple.withOpacity(0.32),
                                GhostPalette.neonPink.withOpacity(0.28),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: GhostPalette.neonPink.withOpacity(0.6),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.auto_awesome_rounded,
                                  color: GhostPalette.amberGold, size: 15),
                              const SizedBox(width: 5),
                              Text(
                                isFa ? 'شانسی!' : 'Surprise',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Large Animated Preview Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: GhostGlassCard(
                    accentColor: accent,
                    borderRadius: 22,
                    reducedMotion: prefs.reducedMotion,
                    blurSigma: 10,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Preview stage
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    accent.withOpacity(0.26),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              alignment: Alignment.center,
                              child: _selectedSignature != null
                                  ? _buildSignatureImage(
                                      _selectedSignature!, 74)
                                  : GhostStickerArtwork(
                                      sticker: _selectedSticker,
                                      size: 78,
                                      sharedAnimation: _sharedAnim,
                                      reducedMotion: prefs.reducedMotion,
                                      intensity: prefs.effectIntensity,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            // Info + controls
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _selectedSignature != null
                                              ? _selectedSignature!.name
                                              : (isFa
                                                  ? _selectedSticker.titleFa
                                                  : _selectedSticker.titleEn),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (_selectedSignature == null)
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 32, minHeight: 32),
                                          icon: Icon(
                                            isFav
                                                ? Icons.star_rounded
                                                : Icons.star_border_rounded,
                                            color: isFav
                                                ? GhostPalette.amberGold
                                                : Colors.white54,
                                            size: 22,
                                          ),
                                          onPressed: () {
                                            HapticFeedback.selectionClick();
                                            GhostTouchPreferencesService
                                                .instance
                                                .toggleFavorite(
                                                    _selectedSticker.id);
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedSignature != null
                                        ? (isFa
                                            ? 'استیکر امضای شخصی'
                                            : 'Custom Signature Sticker')
                                        : _selectedSticker.category
                                            .label(isFa),
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      // Flash toggle pill
                                      InkWell(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          setState(() => _flashOnScreen =
                                              !_flashOnScreen);
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: AnimatedContainer(
                                          duration: GhostMotion.microTap,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 9, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _flashOnScreen
                                                ? GhostPalette.neonPink
                                                    .withOpacity(0.24)
                                                : Colors.white
                                                    .withOpacity(0.06),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: _flashOnScreen
                                                  ? GhostPalette.neonPink
                                                  : Colors.white12,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.bolt_rounded,
                                                size: 14,
                                                color: _flashOnScreen
                                                    ? GhostPalette.neonPink
                                                    : Colors.white54,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                isFa ? 'فلش صفحه' : 'Flash',
                                                style: TextStyle(
                                                  color: _flashOnScreen
                                                      ? Colors.white
                                                      : Colors.white60,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      // Primary Send CTA
                                      InkWell(
                                        onTap: _sendSelected,
                                        borderRadius: BorderRadius.circular(14),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 7),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                accent,
                                                GhostPalette.neonPurple,
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            boxShadow: [
                                              BoxShadow(
                                                color:
                                                    accent.withOpacity(0.35),
                                                blurRadius: 10,
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.send_rounded,
                                                  color: Colors.white,
                                                  size: 15),
                                              const SizedBox(width: 5),
                                              Text(
                                                isFa ? 'ارسال' : 'Send',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_flashOnScreen) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _cycleHologramStyle,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: GhostPalette.electricCyan
                                            .withOpacity(0.35),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(_hologramStyle.icon,
                                            size: 14,
                                            color: GhostPalette.electricCyan),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '${isFa ? "افکت: " : "Effect: "}${_hologramStyle.label(isFa)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const Icon(Icons.sync_rounded,
                                            size: 13, color: Colors.white54),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: _cycleDuration,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Text(
                                    isFa
                                        ? '$_durationSec ثانیه'
                                        : '${_durationSec}s',
                                    style: const TextStyle(
                                      color: GhostPalette.neonGreen,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Search bar (compact)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(color: Colors.white, fontSize: 12.5),
                      decoration: InputDecoration(
                        hintText: isFa
                            ? 'جستجوی نام یا موضوع استیکر...'
                            : 'Search stickers...',
                        hintStyle: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: Colors.white38, size: 17),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white54, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Category tabs
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      _buildTabChip('all', isFa ? 'همه' : 'All',
                          Icons.grid_view_rounded, GhostPalette.electricCyan),
                      _buildTabChip(
                        'favorites',
                        isFa
                            ? 'محبوب (${prefs.favoriteStickerIds.length})'
                            : 'Fav (${prefs.favoriteStickerIds.length})',
                        Icons.star_rounded,
                        GhostPalette.amberGold,
                      ),
                      _buildTabChip('recent', isFa ? 'اخیر' : 'Recent',
                          Icons.history_rounded, GhostPalette.neonPurple),
                      _buildTabChip('signature', isFa ? 'امضاها' : 'Signatures',
                          Icons.draw_rounded, GhostPalette.neonGreen),
                      for (final cat in GhostStickerCategory.values)
                        _buildTabChip(cat.name, cat.label(isFa),
                            _categoryIcon(cat), cat.accentColor),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Content Grid
                Expanded(
                  child: isSignatureTab
                      ? _buildSignatureGrid(isFa, prefs)
                      : items.isEmpty
                          ? Center(
                              child: Text(
                                isFa
                                    ? 'استیکری یافت نشد'
                                    : 'No stickers found',
                                style: const TextStyle(color: Colors.white54),
                              ),
                            )
                          : GridView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 4, 14, 18),
                              itemCount: items.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 0.78,
                              ),
                              itemBuilder: (context, index) {
                                final st = items[index];
                                final isSelected = _selectedSignature == null &&
                                    _selectedSticker.id == st.id;
                                return _buildStickerTile(
                                  st,
                                  isSelected: isSelected,
                                  isFa: isFa,
                                  prefs: prefs,
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _categoryIcon(GhostStickerCategory cat) {
    switch (cat) {
      case GhostStickerCategory.love:
        return Icons.favorite_rounded;
      case GhostStickerCategory.cosmic:
        return Icons.public_rounded;
      case GhostStickerCategory.cyberpunk:
        return Icons.memory_rounded;
      case GhostStickerCategory.cute:
        return Icons.pets_rounded;
      case GhostStickerCategory.presence:
        return Icons.wifi_tethering_rounded;
      case GhostStickerCategory.celebration:
        return Icons.celebration_rounded;
    }
  }

  Widget _buildTabChip(String id, String label, IconData icon, Color color) {
    final active = _activeTab == id;
    return Padding(
      padding: const EdgeInsets.only(right: 7, left: 1),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _activeTab = id);
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: GhostMotion.microTap,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? color.withOpacity(0.24)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? color : Colors.white12,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? color : Colors.white60),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white70,
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStickerTile(
    GhostStickerDef st, {
    required bool isSelected,
    required bool isFa,
    required GhostTouchPreferences prefs,
  }) {
    final isFav = prefs.favoriteStickerIds.contains(st.id);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        HapticFeedback.selectionClick();
        if (isSelected) {
          _sendSelected();
        } else {
          setState(() {
            _selectedSignature = null;
            _selectedSticker = st;
          });
        }
      },
      onDoubleTap: () {
        setState(() {
          _selectedSignature = null;
          _selectedSticker = st;
        });
        _sendSelected();
      },
      child: AnimatedContainer(
        duration: GhostMotion.microTap,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              st.primaryColor.withOpacity(isSelected ? 0.28 : 0.11),
              GhostPalette.darkViolet.withOpacity(0.75),
            ],
          ),
          border: Border.all(
            color: st.primaryColor.withOpacity(isSelected ? 0.95 : 0.28),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: st.primaryColor.withOpacity(0.32),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: GhostStickerArtwork(
                      sticker: st,
                      size: 56,
                      sharedAnimation: _sharedAnim,
                      reducedMotion: prefs.reducedMotion,
                      intensity: prefs.effectIntensity,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isFa ? st.titleFa : st.titleEn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.85),
                    fontSize: 9.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (isFav)
              const Positioned(
                top: 2,
                right: 3,
                child: Icon(Icons.star_rounded,
                    color: GhostPalette.amberGold, size: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureImage(SignatureSticker sig, double size) {
    final bytes = _decodeSignature(sig);
    if (bytes == null) {
      return Icon(Icons.broken_image_rounded,
          color: Colors.white38, size: size * 0.6);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildSignatureGrid(bool isFa, GhostTouchPreferences prefs) {
    final sigs = prefs.signatureStickers;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
      itemCount: sigs.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.88,
      ),
      itemBuilder: (context, index) {
        if (index == 0) {
          return InkWell(
            onTap: _handleCreateSignature,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: GhostPalette.neonGreen.withOpacity(0.09),
                border: Border.all(
                  color: GhostPalette.neonGreen.withOpacity(0.65),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_circle_outline_rounded,
                      color: GhostPalette.neonGreen, size: 34),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      isFa ? 'ساخت استیکر جدید' : 'Create New',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final sig = sigs[index - 1];
        final isSelected = _selectedSignature?.id == sig.id;
        return InkWell(
          onTap: () {
            if (isSelected) {
              _sendSelected();
            } else {
              setState(() => _selectedSignature = sig);
            }
          },
          onDoubleTap: () {
            setState(() => _selectedSignature = sig);
            _sendSelected();
          },
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: GhostPalette.darkViolet.withOpacity(0.75),
              border: Border.all(
                color: isSelected
                    ? GhostPalette.electricCyan
                    : Colors.white.withOpacity(0.15),
                width: isSelected ? 1.8 : 1,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(child: Center(child: _buildSignatureImage(sig, 64))),
                    const SizedBox(height: 4),
                    Text(
                      sig.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: InkWell(
                    onTap: () => GhostTouchPreferencesService.instance
                        .removeSignatureSticker(sig.id),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 12, color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
