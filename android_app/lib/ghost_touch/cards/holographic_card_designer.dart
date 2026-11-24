import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ghost_touch_theme.dart';
import '../models/hologram_models.dart';
import '../stickers/ghost_sticker_catalog.dart';
import '../stickers/ghost_sticker_painter.dart';
import 'holographic_card_renderer.dart';

class FlashCardResult {
  final FlashCardData cardData;
  final bool flashOnScreen;

  const FlashCardResult({
    required this.cardData,
    required this.flashOnScreen,
  });
}

/// Interactive 12-template Holographic Message Card Designer (Phase 4).
class HolographicCardDesigner extends StatefulWidget {
  final bool isFa;
  final bool initialFlash;

  const HolographicCardDesigner({
    super.key,
    required this.isFa,
    this.initialFlash = true,
  });

  static Future<FlashCardResult?> open(
    BuildContext context, {
    required bool isFa,
    bool initialFlash = true,
  }) {
    return Navigator.of(context).push<FlashCardResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => HolographicCardDesigner(
          isFa: isFa,
          initialFlash: initialFlash,
        ),
      ),
    );
  }

  @override
  State<HolographicCardDesigner> createState() =>
      _HolographicCardDesignerState();
}

class _HolographicCardDesignerState extends State<HolographicCardDesigner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sharedAnim;
  final TextEditingController _textCtrl = TextEditingController();

  late FlashCardData _card;
  late bool _flashOnScreen;
  int _activeTab = 0;

  static const List<String> _textColorHexPresets = [
    '#FFFFFF',
    '#FFE4F2',
    '#A5F3FC',
    '#FEF08A',
    '#BBF7D0',
    '#DDD6FE',
    '#FF8EC7',
    '#00E5FF',
  ];

  static const List<String> _decorativePresets = [
    'sparkles',
    'hearts',
    'orbit',
    'cyberGrid',
    'confetti',
    'bokeh',
    'none',
  ];

  String _decorLabel(String preset, bool isFa) {
    switch (preset) {
      case 'none':
        return isFa ? 'بدون افکت' : 'None';
      case 'hearts':
        return isFa ? 'قلب‌های ریز' : 'Hearts';
      case 'orbit':
        return isFa ? 'مدار نوری' : 'Orbit';
      case 'cyberGrid':
        return isFa ? 'شبکه سایبری' : 'Cyber Grid';
      case 'confetti':
        return isFa ? 'کاغذ رنگی' : 'Confetti';
      case 'bokeh':
        return isFa ? 'حباب بوکه' : 'Bokeh';
      case 'sparkles':
      default:
        return isFa ? 'درخشش ستاره' : 'Sparkles';
    }
  }

  @override
  void initState() {
    super.initState();
    final prefs = GhostTouchPreferencesService.instance.current;
    _flashOnScreen = widget.initialFlash;
    _card = FlashCardData(
      template: FlashCardTemplate.romanticNeonHeart,
      text: widget.isFa ? 'به فکرتم، دلم برات تنگ شده ✨' : 'Thinking of you right now ✨',
      stickerId: 'love_glowing_heart',
      hologramStyle: prefs.defaultStyle,
      durationSec: prefs.displayDurationSec,
      accentColorHex: GhostPalette.toHex(
        FlashCardTemplate.romanticNeonHeart.accentColor,
      ),
    );
    _textCtrl.text = _card.text;
    _sharedAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _sharedAnim.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _sendCard() {
    final finalText = _textCtrl.text.trim();
    if (finalText.isEmpty && (_card.stickerId == null || _card.stickerId!.isEmpty)) {
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.pop(
      context,
      FlashCardResult(
        cardData: _card.copyWith(
          text: finalText.isEmpty
              ? (widget.isFa ? 'سورپرایز هولوگرافیک' : 'Holographic Surprise')
              : finalText,
        ),
        flashOnScreen: _flashOnScreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFa = widget.isFa;
    final accent = GhostPalette.fromHex(
      _card.accentColorHex,
      fallback: _card.template.accentColor,
    );

    return Directionality(
      textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: GhostPalette.deepSpace,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isFa
                                ? 'طراح کارت پیام هولوگرافیک'
                                : 'Holographic Card Studio',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            isFa
                                ? '۱۲ قالب زنده • تایپوگرافی و افکت نئون'
                                : '12 live templates • typography & neon FX',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: _sendCard,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [accent, GhostPalette.neonPurple],
                          ),
                          boxShadow: [
                            BoxShadow(
                                color: accent.withOpacity(0.35), blurRadius: 12),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome_rounded,
                                color: Colors.white, size: 15),
                            const SizedBox(width: 6),
                            Text(
                              isFa ? 'ارسال کارت' : 'Send Card',
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
              ),

              // Live Card Preview
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: HolographicCardRenderer(
                        data: _card.copyWith(text: _textCtrl.text),
                        isFa: isFa,
                        sharedAnimation: _sharedAnim,
                      ),
                    ),
                  ),
                ),
              ),

              // Designer Control Dock
              Container(
                margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: GhostPalette.darkViolet.withOpacity(0.94),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _tabBtn(0, Icons.style_rounded,
                            isFa ? 'قالب‌ها (۱۲)' : 'Templates'),
                        _tabBtn(1, Icons.text_fields_rounded,
                            isFa ? 'متن و فونت' : 'Text'),
                        _tabBtn(2, Icons.auto_fix_high_rounded,
                            isFa ? 'استیکر و قاب' : 'Decor'),
                        _tabBtn(3, Icons.bolt_rounded,
                            isFa ? 'افکت و فلش' : 'Hologram'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 184,
                      child: _buildTabContent(isFa, accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabBtn(int idx, IconData icon, String label) {
    final active = _activeTab == idx;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _activeTab = idx);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? GhostPalette.electricCyan.withOpacity(0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? GhostPalette.electricCyan : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 16,
                  color:
                      active ? GhostPalette.electricCyan : Colors.white54),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white60,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(bool isFa, Color accent) {
    switch (_activeTab) {
      case 0:
        return GridView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: FlashCardTemplate.values.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.48,
          ),
          itemBuilder: (_, i) {
            final tpl = FlashCardTemplate.values[i];
            final active = _card.template == tpl;
            return InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _card = _card.copyWith(
                    template: tpl,
                    accentColorHex: GhostPalette.toHex(tpl.accentColor),
                  );
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(colors: tpl.gradientColors),
                  border: Border.all(
                    color: active ? tpl.accentColor : Colors.white12,
                    width: active ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: tpl.accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tpl.label(isFa),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

      case 1:
        return SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _textCtrl,
                maxLines: 2,
                maxLength: 140,
                onChanged: (v) =>
                    setState(() => _card = _card.copyWith(text: v)),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: isFa
                      ? 'پیام عاشقانه یا خاص خود را بنویسید...'
                      : 'Write your holographic message...',
                  hintStyle:
                      const TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // Alignment cycler
                  InkWell(
                    onTap: () {
                      final aligns = [
                        TextAlign.center,
                        TextAlign.right,
                        TextAlign.left,
                      ];
                      final idx = aligns.indexOf(_card.textAlign);
                      final next = aligns[(idx + 1) % aligns.length];
                      setState(() => _card = _card.copyWith(textAlign: next));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _card.textAlign == TextAlign.center
                            ? Icons.format_align_center_rounded
                            : (_card.textAlign == TextAlign.right
                                ? Icons.format_align_right_rounded
                                : Icons.format_align_left_rounded),
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: CardFontStyle.values.map((f) {
                          final active = _card.fontStyle == f;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                f.name.toUpperCase(),
                                style: const TextStyle(fontSize: 10),
                              ),
                              selected: active,
                              selectedColor: accent.withOpacity(0.32),
                              onSelected: (_) => setState(
                                  () => _card = _card.copyWith(fontStyle: f)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    isFa ? 'رنگ متن:' : 'Text:',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SizedBox(
                      height: 26,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _textColorHexPresets.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final hex = _textColorHexPresets[i];
                          final c = GhostPalette.fromHex(hex, fallback: Colors.white);
                          final active =
                              _card.textColorHex.toUpperCase() == hex.toUpperCase();
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _card = _card.copyWith(textColorHex: hex));
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: active
                                      ? GhostPalette.electricCyan
                                      : Colors.white30,
                                  width: active ? 2.4 : 1,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    isFa ? 'نور حاشیه:' : 'Accent:',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SizedBox(
                      height: 26,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: GhostPalette.presets.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final c = GhostPalette.presets[i];
                          final hex = GhostPalette.toHex(c);
                          final active =
                              _card.accentColorHex.toUpperCase() == hex.toUpperCase();
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _card = _card.copyWith(accentColorHex: hex));
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: active ? Colors.white : Colors.white24,
                                  width: active ? 2.4 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: c.withOpacity(0.45),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case 2:
        const stickers = GhostStickerCatalog.all;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isFa ? 'قاب:' : 'Border:',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: CardBorderEffect.values.map((b) {
                        final active = _card.borderEffect == b;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(b.name, style: const TextStyle(fontSize: 10)),
                            selected: active,
                            selectedColor: accent.withOpacity(0.32),
                            onSelected: (_) => setState(
                                () => _card = _card.copyWith(borderEffect: b)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  isFa ? 'تزئین:' : 'Decor:',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _decorativePresets.map((preset) {
                        final active = _card.decorativePreset == preset;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              _decorLabel(preset, isFa),
                              style: const TextStyle(fontSize: 10),
                            ),
                            selected: active,
                            selectedColor: GhostPalette.electricCyan.withOpacity(0.28),
                            onSelected: (_) => setState(() =>
                                _card = _card.copyWith(decorativePreset: preset)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: stickers.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    final active = _card.stickerId == null;
                    return InkWell(
                      onTap: () => setState(
                          () => _card = _card.copyWith(clearSticker: true)),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: active ? Colors.white : Colors.white12,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.block_rounded,
                                color: Colors.white54, size: 22),
                            const SizedBox(height: 4),
                            Text(
                              isFa ? 'بدون' : 'None',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final st = stickers[i - 1];
                  final active = _card.stickerId == st.id;
                  return InkWell(
                    onTap: () => setState(
                        () => _card = _card.copyWith(stickerId: st.id)),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 68,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: st.primaryColor.withOpacity(active ? 0.24 : 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: active ? st.primaryColor : Colors.white12,
                        ),
                      ),
                      child: GhostStickerArtwork(
                        sticker: st,
                        size: 52,
                        sharedAnimation: _sharedAnim,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );

      default:
        return Column(
          children: [
            Row(
              children: [
                Switch(
                  value: _flashOnScreen,
                  activeColor: GhostPalette.neonPink,
                  onChanged: (v) => setState(() => _flashOnScreen = v),
                ),
                Expanded(
                  child: Text(
                    isFa
                        ? 'نمایش هولوگرام فوری روی صفحه مخاطب (حتی روی قفل)'
                        : 'Flash overlay on recipient screen & lock screen',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: HologramStyle.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final st = HologramStyle.values[i];
                  final active = _card.hologramStyle == st;
                  return ChoiceChip(
                    avatar: Icon(st.icon, size: 14, color: Colors.white),
                    label: Text(
                      st.label(isFa),
                      style: const TextStyle(fontSize: 10.5),
                    ),
                    selected: active,
                    selectedColor: GhostPalette.electricCyan.withOpacity(0.3),
                    onSelected: (_) => setState(
                        () => _card = _card.copyWith(hologramStyle: st)),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [5, 7, 10, 15, 20].map((sec) {
                  final active = _card.durationSec == sec;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () => setState(
                          () => _card = _card.copyWith(durationSec: sec)),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: active
                              ? GhostPalette.neonGreen.withOpacity(0.24)
                              : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: active
                                ? GhostPalette.neonGreen
                                : Colors.white12,
                          ),
                        ),
                        child: Text(
                          isFa ? '$sec ثانیه' : '${sec}s',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
    }
  }
}
