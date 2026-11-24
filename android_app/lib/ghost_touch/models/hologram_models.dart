import 'dart:convert';
import 'package:flutter/material.dart';
import '../../security/auto_lock_service.dart';
import '../../security/keystore_service.dart';
import '../ghost_touch_theme.dart';

enum HologramStyle {
  floatingHeart,
  holographicCard,
  cosmicPortal,
  particleAssembly,
  neonDrawingReveal,
  floatingSticker,
  digitalWave,
  surpriseBurst,
}

extension HologramStyleExt on HologramStyle {
  String label(bool isFa) {
    switch (this) {
      case HologramStyle.floatingHeart:
        return isFa ? 'قلب شناور' : 'Floating Heart';
      case HologramStyle.holographicCard:
        return isFa ? 'کارت هولوگرافیک' : 'Holo Card';
      case HologramStyle.cosmicPortal:
        return isFa ? 'پورتال کیهانی' : 'Cosmic Portal';
      case HologramStyle.particleAssembly:
        return isFa ? 'تجمع ذرات نور' : 'Particle Swarm';
      case HologramStyle.neonDrawingReveal:
        return isFa ? 'اسکن نئونی' : 'Neon Reveal';
      case HologramStyle.floatingSticker:
        return isFa ? 'استیکر معلق' : 'Float Sticker';
      case HologramStyle.digitalWave:
        return isFa ? 'موج دیجیتال' : 'Digital Wave';
      case HologramStyle.surpriseBurst:
        return isFa ? 'انفجار غافلگیری' : 'Surprise Burst';
    }
  }

  IconData get icon {
    switch (this) {
      case HologramStyle.floatingHeart:
        return Icons.favorite_rounded;
      case HologramStyle.holographicCard:
        return Icons.style_rounded;
      case HologramStyle.cosmicPortal:
        return Icons.cyclone_rounded;
      case HologramStyle.particleAssembly:
        return Icons.grain_rounded;
      case HologramStyle.neonDrawingReveal:
        return Icons.qr_code_scanner_rounded;
      case HologramStyle.floatingSticker:
        return Icons.auto_awesome_rounded;
      case HologramStyle.digitalWave:
        return Icons.waves_rounded;
      case HologramStyle.surpriseBurst:
        return Icons.celebration_rounded;
    }
  }

  static HologramStyle parse(String? name) {
    if (name == null || name.isEmpty) return HologramStyle.holographicCard;
    return HologramStyle.values.firstWhere(
      (e) => e.name == name,
      orElse: () => HologramStyle.holographicCard,
    );
  }
}

enum FlashCardTemplate {
  romanticNeonHeart,
  cosmicMessage,
  pinkCrystal,
  purpleGalaxy,
  cyberpunkEnergy,
  minimalElegant,
  auroraCard,
  glassmorphismCard,
  floatingFlower,
  animatedStarField,
  liquidNeon,
  digitalHeartbeat,
}

extension FlashCardTemplateExt on FlashCardTemplate {
  String label(bool isFa) {
    switch (this) {
      case FlashCardTemplate.romanticNeonHeart:
        return isFa ? 'قلب نئونی رمانتیک' : 'Romantic Heart';
      case FlashCardTemplate.cosmicMessage:
        return isFa ? 'پیام کیهانی' : 'Cosmic Message';
      case FlashCardTemplate.pinkCrystal:
        return isFa ? 'کریستال صورتی' : 'Pink Crystal';
      case FlashCardTemplate.purpleGalaxy:
        return isFa ? 'کهکشان بنفش' : 'Purple Galaxy';
      case FlashCardTemplate.cyberpunkEnergy:
        return isFa ? 'انرژی سایبرپانک' : 'Cyber Energy';
      case FlashCardTemplate.minimalElegant:
        return isFa ? 'مینیمال لوکس' : 'Minimal Luxury';
      case FlashCardTemplate.auroraCard:
        return isFa ? 'شفق قطبی' : 'Aurora Veil';
      case FlashCardTemplate.glassmorphismCard:
        return isFa ? 'شیشه‌ای شفاف' : 'Prism Glass';
      case FlashCardTemplate.floatingFlower:
        return isFa ? 'گلبرگ شناور' : 'Floating Flora';
      case FlashCardTemplate.animatedStarField:
        return isFa ? 'بارش ستاره' : 'Starfield';
      case FlashCardTemplate.liquidNeon:
        return isFa ? 'نئون مایع' : 'Liquid Neon';
      case FlashCardTemplate.digitalHeartbeat:
        return isFa ? 'نبض دیجیتال' : 'Digital Pulse';
    }
  }

  Color get accentColor {
    switch (this) {
      case FlashCardTemplate.romanticNeonHeart:
        return GhostPalette.neonPink;
      case FlashCardTemplate.cosmicMessage:
        return GhostPalette.electricBlue;
      case FlashCardTemplate.pinkCrystal:
        return const Color(0xFFFF6EC7);
      case FlashCardTemplate.purpleGalaxy:
        return GhostPalette.neonPurple;
      case FlashCardTemplate.cyberpunkEnergy:
        return GhostPalette.electricCyan;
      case FlashCardTemplate.minimalElegant:
        return const Color(0xFFE2E8F0);
      case FlashCardTemplate.auroraCard:
        return GhostPalette.neonGreen;
      case FlashCardTemplate.glassmorphismCard:
        return const Color(0xFF7DD3FC);
      case FlashCardTemplate.floatingFlower:
        return const Color(0xFFFF758F);
      case FlashCardTemplate.animatedStarField:
        return GhostPalette.amberGold;
      case FlashCardTemplate.liquidNeon:
        return const Color(0xFFFF2A85);
      case FlashCardTemplate.digitalHeartbeat:
        return GhostPalette.neonGreen;
    }
  }

  List<Color> get gradientColors {
    switch (this) {
      case FlashCardTemplate.romanticNeonHeart:
        return [const Color(0xFF340B29), const Color(0xFF170B22), GhostPalette.deepSpace];
      case FlashCardTemplate.cosmicMessage:
        return [const Color(0xFF0A1D4E), const Color(0xFF0E102C), GhostPalette.deepSpace];
      case FlashCardTemplate.pinkCrystal:
        return [const Color(0xFF3E103A), const Color(0xFF1E1032), const Color(0xFF0D0A1B)];
      case FlashCardTemplate.purpleGalaxy:
        return [const Color(0xFF28104E), GhostPalette.darkViolet, GhostPalette.deepSpace];
      case FlashCardTemplate.cyberpunkEnergy:
        return [const Color(0xFF072B3A), const Color(0xFF0D142B), GhostPalette.deepSpace];
      case FlashCardTemplate.minimalElegant:
        return [const Color(0xFF1B1E2E), const Color(0xFF11131E), const Color(0xFF090A10)];
      case FlashCardTemplate.auroraCard:
        return [const Color(0xFF062C28), const Color(0xFF0D1B38), GhostPalette.deepSpace];
      case FlashCardTemplate.glassmorphismCard:
        return [const Color(0xFF142847), const Color(0xFF181930), const Color(0xFF0B0E1B)];
      case FlashCardTemplate.floatingFlower:
        return [const Color(0xFF3A1025), const Color(0xFF1E1128), GhostPalette.deepSpace];
      case FlashCardTemplate.animatedStarField:
        return [const Color(0xFF211834), const Color(0xFF0E132B), GhostPalette.deepSpace];
      case FlashCardTemplate.liquidNeon:
        return [const Color(0xFF3A082A), const Color(0xFF12183C), GhostPalette.deepSpace];
      case FlashCardTemplate.digitalHeartbeat:
        return [const Color(0xFF082722), const Color(0xFF131325), GhostPalette.deepSpace];
    }
  }

  static FlashCardTemplate parse(String? name) {
    if (name == null || name.isEmpty) return FlashCardTemplate.romanticNeonHeart;
    return FlashCardTemplate.values.firstWhere(
      (e) => e.name == name,
      orElse: () => FlashCardTemplate.romanticNeonHeart,
    );
  }
}

enum OverlayPosition { top, center, bottom }

enum CardBorderEffect { glow, doublePrism, pulse, minimal }

enum CardFontStyle { modern, serif, mono, display }

class FlashCardData {
  final FlashCardTemplate template;
  final String text;
  final TextAlign textAlign;
  final CardFontStyle fontStyle;
  final String textColorHex;
  final String accentColorHex;
  final CardBorderEffect borderEffect;
  final String? stickerId;
  final HologramStyle hologramStyle;
  final int durationSec;
  final String decorativePreset;

  const FlashCardData({
    this.template = FlashCardTemplate.romanticNeonHeart,
    required this.text,
    this.textAlign = TextAlign.center,
    this.fontStyle = CardFontStyle.modern,
    this.textColorHex = '#FFFFFF',
    this.accentColorHex = '#FF3D9A',
    this.borderEffect = CardBorderEffect.glow,
    this.stickerId,
    this.hologramStyle = HologramStyle.holographicCard,
    this.durationSec = 7,
    this.decorativePreset = 'sparkles',
  });

  FlashCardData copyWith({
    FlashCardTemplate? template,
    String? text,
    TextAlign? textAlign,
    CardFontStyle? fontStyle,
    String? textColorHex,
    String? accentColorHex,
    CardBorderEffect? borderEffect,
    String? stickerId,
    bool clearSticker = false,
    HologramStyle? hologramStyle,
    int? durationSec,
    String? decorativePreset,
  }) {
    return FlashCardData(
      template: template ?? this.template,
      text: text ?? this.text,
      textAlign: textAlign ?? this.textAlign,
      fontStyle: fontStyle ?? this.fontStyle,
      textColorHex: textColorHex ?? this.textColorHex,
      accentColorHex: accentColorHex ?? this.accentColorHex,
      borderEffect: borderEffect ?? this.borderEffect,
      stickerId: clearSticker ? null : (stickerId ?? this.stickerId),
      hologramStyle: hologramStyle ?? this.hologramStyle,
      durationSec: durationSec ?? this.durationSec,
      decorativePreset: decorativePreset ?? this.decorativePreset,
    );
  }

  Map<String, dynamic> toJson() => {
        'template': template.name,
        'text': text,
        'textAlign': textAlign.name,
        'fontStyle': fontStyle.name,
        'textColorHex': textColorHex,
        'accentColorHex': accentColorHex,
        'borderEffect': borderEffect.name,
        if (stickerId != null) 'stickerId': stickerId,
        'hologramStyle': hologramStyle.name,
        'durationSec': durationSec,
        'decorativePreset': decorativePreset,
      };

  String toJsonString() => jsonEncode(toJson());

  factory FlashCardData.fromJson(Map<String, dynamic> json) {
    final alignStr = json['textAlign'] as String? ?? 'center';
    final fontStr = json['fontStyle'] as String? ?? 'modern';
    final borderStr = json['borderEffect'] as String? ?? 'glow';
    return FlashCardData(
      template: FlashCardTemplateExt.parse(json['template'] as String?),
      text: (json['text'] as String?) ?? '',
      textAlign: TextAlign.values.firstWhere(
        (e) => e.name == alignStr,
        orElse: () => TextAlign.center,
      ),
      fontStyle: CardFontStyle.values.firstWhere(
        (e) => e.name == fontStr,
        orElse: () => CardFontStyle.modern,
      ),
      textColorHex: (json['textColorHex'] as String?) ?? '#FFFFFF',
      accentColorHex: (json['accentColorHex'] as String?) ?? '#FF3D9A',
      borderEffect: CardBorderEffect.values.firstWhere(
        (e) => e.name == borderStr,
        orElse: () => CardBorderEffect.glow,
      ),
      stickerId: json['stickerId'] as String?,
      hologramStyle: HologramStyleExt.parse(json['hologramStyle'] as String?),
      durationSec: (json['durationSec'] as int?) ?? 7,
      decorativePreset: (json['decorativePreset'] as String?) ?? 'sparkles',
    );
  }

  static FlashCardData? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return FlashCardData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

class SignatureSticker {
  final String id;
  final String name;
  final String pngBase64;
  final int createdAt;

  const SignatureSticker({
    required this.id,
    required this.name,
    required this.pngBase64,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pngBase64': pngBase64,
        'createdAt': createdAt,
      };

  factory SignatureSticker.fromJson(Map<String, dynamic> json) {
    return SignatureSticker(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'My Sticker',
      pngBase64: (json['pngBase64'] as String?) ?? '',
      createdAt: (json['createdAt'] as int?) ?? 0,
    );
  }
}

class GhostTouchPreferences {
  final HologramStyle defaultStyle;
  final OverlayPosition position;
  final int displayDurationSec;
  final bool vibrateEnabled;
  final bool soundEnabled;
  final double effectIntensity;
  final bool reducedMotion;
  final List<String> favoriteStickerIds;
  final List<String> recentStickerIds;
  final List<SignatureSticker> signatureStickers;

  const GhostTouchPreferences({
    this.defaultStyle = HologramStyle.holographicCard,
    this.position = OverlayPosition.center,
    this.displayDurationSec = 7,
    this.vibrateEnabled = true,
    this.soundEnabled = true,
    this.effectIntensity = 0.85,
    this.reducedMotion = false,
    this.favoriteStickerIds = const ['love_glowing_heart', 'presence_miss_you', 'cosmic_galaxy_portal'],
    this.recentStickerIds = const [],
    this.signatureStickers = const [],
  });

  GhostTouchPreferences copyWith({
    HologramStyle? defaultStyle,
    OverlayPosition? position,
    int? displayDurationSec,
    bool? vibrateEnabled,
    bool? soundEnabled,
    double? effectIntensity,
    bool? reducedMotion,
    List<String>? favoriteStickerIds,
    List<String>? recentStickerIds,
    List<SignatureSticker>? signatureStickers,
  }) {
    return GhostTouchPreferences(
      defaultStyle: defaultStyle ?? this.defaultStyle,
      position: position ?? this.position,
      displayDurationSec: displayDurationSec ?? this.displayDurationSec,
      vibrateEnabled: vibrateEnabled ?? this.vibrateEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      effectIntensity: effectIntensity ?? this.effectIntensity,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      favoriteStickerIds: favoriteStickerIds ?? this.favoriteStickerIds,
      recentStickerIds: recentStickerIds ?? this.recentStickerIds,
      signatureStickers: signatureStickers ?? this.signatureStickers,
    );
  }

  Map<String, dynamic> toJson() => {
        'defaultStyle': defaultStyle.name,
        'position': position.name,
        'displayDurationSec': displayDurationSec,
        'vibrateEnabled': vibrateEnabled,
        'soundEnabled': soundEnabled,
        'effectIntensity': effectIntensity,
        'reducedMotion': reducedMotion,
        'favoriteStickerIds': favoriteStickerIds,
        'recentStickerIds': recentStickerIds,
        'signatureStickers': signatureStickers.map((s) => s.toJson()).toList(),
      };

  factory GhostTouchPreferences.fromJson(Map<String, dynamic> json) {
    final posStr = json['position'] as String? ?? 'center';
    final favs = (json['favoriteStickerIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['love_glowing_heart', 'presence_miss_you', 'cosmic_galaxy_portal'];
    final recs = (json['recentStickerIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    final sigs = (json['signatureStickers'] as List<dynamic>?)
            ?.map((e) => SignatureSticker.fromJson(e as Map<String, dynamic>))
            .where((s) => s.pngBase64.isNotEmpty)
            .toList() ??
        const [];

    return GhostTouchPreferences(
      defaultStyle: HologramStyleExt.parse(json['defaultStyle'] as String?),
      position: OverlayPosition.values.firstWhere(
        (e) => e.name == posStr,
        orElse: () => OverlayPosition.center,
      ),
      displayDurationSec: ((json['displayDurationSec'] as int?) ?? 7).clamp(3, 30),
      vibrateEnabled: json['vibrateEnabled'] != false,
      soundEnabled: json['soundEnabled'] != false,
      effectIntensity: ((json['effectIntensity'] as num?)?.toDouble() ?? 0.85).clamp(0.2, 1.0),
      reducedMotion: json['reducedMotion'] == true,
      favoriteStickerIds: favs,
      recentStickerIds: recs,
      signatureStickers: sigs,
    );
  }

  Map<String, dynamic> toNativeSyncMap() => {
        'position': position.name,
        'displayDurationSec': displayDurationSec,
        'vibrateEnabled': vibrateEnabled,
        'soundEnabled': soundEnabled,
        'effectIntensity': effectIntensity,
        'reducedMotion': reducedMotion,
      };
}

class GhostTouchPreferencesService {
  static final GhostTouchPreferencesService instance = GhostTouchPreferencesService._();
  GhostTouchPreferencesService._();

  final KeystoreService _keystore = KeystoreService();
  final ValueNotifier<GhostTouchPreferences> notifier =
      ValueNotifier<GhostTouchPreferences>(const GhostTouchPreferences());
  bool _loaded = false;

  GhostTouchPreferences get current => notifier.value;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _keystore.getGhostTouchPrefsJson();
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        notifier.value = GhostTouchPreferences.fromJson(map);
      }
      await AutoLockService().syncGhostTouchNativePrefs(notifier.value.toNativeSyncMap());
    } catch (_) {}
  }

  Future<void> update(GhostTouchPreferences next) async {
    notifier.value = next;
    _loaded = true;
    try {
      await _keystore.saveGhostTouchPrefsJson(jsonEncode(next.toJson()));
      await AutoLockService().syncGhostTouchNativePrefs(next.toNativeSyncMap());
    } catch (_) {}
  }

  Future<void> toggleFavorite(String stickerId) async {
    final curr = List<String>.from(current.favoriteStickerIds);
    if (curr.contains(stickerId)) {
      curr.remove(stickerId);
    } else {
      curr.insert(0, stickerId);
    }
    await update(current.copyWith(favoriteStickerIds: curr));
  }

  Future<void> recordRecentSticker(String stickerId) async {
    final curr = List<String>.from(current.recentStickerIds)..remove(stickerId);
    curr.insert(0, stickerId);
    if (curr.length > 16) curr.removeRange(16, curr.length);
    await update(current.copyWith(recentStickerIds: curr));
  }

  Future<void> addSignatureSticker(SignatureSticker sig) async {
    final curr = List<SignatureSticker>.from(current.signatureStickers)..insert(0, sig);
    if (curr.length > 12) curr.removeRange(12, curr.length);
    await update(current.copyWith(signatureStickers: curr));
  }

  Future<void> removeSignatureSticker(String id) async {
    final curr = current.signatureStickers.where((s) => s.id != id).toList();
    await update(current.copyWith(signatureStickers: curr));
  }
}

class GhostReactionMeta {
  final String key;
  final String titleFa;
  final String titleEn;
  final Color color;
  final IconData icon;
  final String stickerId;

  const GhostReactionMeta({
    required this.key,
    required this.titleFa,
    required this.titleEn,
    required this.color,
    required this.icon,
    required this.stickerId,
  });

  static const GhostReactionMeta megaHeart = GhostReactionMeta(
    key: 'mega_heart',
    titleFa: 'شوک تپش قلب زنده!',
    titleEn: 'Mega Heartbeat Shock!',
    color: GhostPalette.neonPink,
    icon: Icons.favorite_rounded,
    stickerId: 'love_beating_heart',
  );

  static const GhostReactionMeta heart = GhostReactionMeta(
    key: 'heart',
    titleFa: 'ارسال عشق و قلب نئونی',
    titleEn: 'Glowing Heart Love',
    color: GhostPalette.neonPink,
    icon: Icons.favorite_rounded,
    stickerId: 'love_glowing_heart',
  );

  static const GhostReactionMeta spark = GhostReactionMeta(
    key: 'spark',
    titleFa: 'جرقه طلایی و ستاره',
    titleEn: 'Golden Sparkle Burst',
    color: GhostPalette.amberGold,
    icon: Icons.auto_awesome_rounded,
    stickerId: 'celebrate_light_burst',
  );

  static const GhostReactionMeta bolt = GhostReactionMeta(
    key: 'bolt',
    titleFa: 'موج انرژی سایبری!',
    titleEn: 'Cyber Volt Surge!',
    color: GhostPalette.electricCyan,
    icon: Icons.bolt_rounded,
    stickerId: 'cyber_lightning',
  );

  static const GhostReactionMeta hug = GhostReactionMeta(
    key: 'hug',
    titleFa: 'بغل مجازی گرم!',
    titleEn: 'Warm Virtual Hug!',
    color: GhostPalette.neonGreen,
    icon: Icons.volunteer_activism_rounded,
    stickerId: 'presence_virtual_hug',
  );

  static GhostReactionMeta of(String? key) {
    switch (key) {
      case 'mega_heart':
        return megaHeart;
      case 'spark':
        return spark;
      case 'bolt':
        return bolt;
      case 'hug':
        return hug;
      case 'heart':
      default:
        return heart;
    }
  }
}
