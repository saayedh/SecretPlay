import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secretplay/chat/chat_message.dart';
import 'package:secretplay/chat/widgets/cyber_sticker_sheet.dart';
import 'package:secretplay/ghost_touch/cards/holographic_card_designer.dart';
import 'package:secretplay/ghost_touch/cards/holographic_card_renderer.dart';
import 'package:secretplay/ghost_touch/drawing/drawing_canvas_painter.dart';
import 'package:secretplay/ghost_touch/drawing/drawing_models.dart';
import 'package:secretplay/ghost_touch/drawing/ultimate_drawing_studio.dart';
import 'package:secretplay/ghost_touch/ghost_touch_theme.dart';
import 'package:secretplay/ghost_touch/models/hologram_models.dart';
import 'package:secretplay/ghost_touch/overlay/floating_hologram_experience.dart';
import 'package:secretplay/ghost_touch/stickers/ghost_sticker_catalog.dart';
import 'package:secretplay/ghost_touch/stickers/ghost_sticker_painter.dart';
import 'package:secretplay/ghost_touch/stickers/ghost_sticker_studio.dart';

void main() {
  group('GhostStickerCatalog', () {
    test('contains >= 60 unique animated vector stickers across all 6 categories', () {
      const all = GhostStickerCatalog.all;
      expect(all.length, greaterThanOrEqualTo(60));

      final ids = all.map((e) => e.id).toSet();
      expect(ids.length, equals(all.length));

      for (final cat in GhostStickerCategory.values) {
        final items = GhostStickerCatalog.byCategory(cat);
        expect(items.length, greaterThanOrEqualTo(8),
            reason: 'Category ${cat.name} should have at least 8 stickers');
      }
    });

    test('resolves legacy v1 sticker IDs via GhostStickerCatalog and CyberStickerCatalog', () {
      final legacyIds = [
        'heart_pulse',
        'kiss_neon',
        'cyber_hug',
        'lol_dead',
        'omw_now',
        'diamond_vip',
      ];
      for (final legacyId in legacyIds) {
        final resolved = GhostStickerCatalog.findById(legacyId);
        expect(resolved.id, isNotEmpty);
        final compat = CyberStickerCatalog.findById(legacyId);
        expect(compat.id, equals(resolved.id));
      }
    });

    test('all 66 GhostStickerPainter motifs paint cleanly onto Canvas without errors',
        () {
      const progressPoints = [0.0, 0.25, 0.5, 0.85];
      for (final st in GhostStickerCatalog.all) {
        for (final p in progressPoints) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          GhostStickerPainter(sticker: st, progress: p)
              .paint(canvas, const Size(96, 96));
          final pic = recorder.endRecording();
          pic.dispose();
        }
      }
    });
  });

  group('FlashCardData & EphemeralChatMessage serialization', () {
    test('FlashCardData JSON round-trip preserves all fields', () {
      const card = FlashCardData(
        template: FlashCardTemplate.auroraCard,
        text: 'دلم برات تنگ شده ✨',
        textAlign: TextAlign.right,
        fontStyle: CardFontStyle.serif,
        textColorHex: '#A5F3FC',
        accentColorHex: '#00FFA3',
        borderEffect: CardBorderEffect.doublePrism,
        stickerId: 'love_glowing_heart',
        hologramStyle: HologramStyle.cosmicPortal,
        durationSec: 12,
        decorativePreset: 'aurora',
      );
      final encoded = card.toJsonString();
      final decoded = FlashCardData.fromJsonString(encoded)!;

      expect(decoded.template, equals(FlashCardTemplate.auroraCard));
      expect(decoded.text, equals('دلم برات تنگ شده ✨'));
      expect(decoded.textAlign, equals(TextAlign.right));
      expect(decoded.fontStyle, equals(CardFontStyle.serif));
      expect(decoded.textColorHex, equals('#A5F3FC'));
      expect(decoded.accentColorHex, equals('#00FFA3'));
      expect(decoded.borderEffect, equals(CardBorderEffect.doublePrism));
      expect(decoded.stickerId, equals('love_glowing_heart'));
      expect(decoded.hologramStyle, equals(HologramStyle.cosmicPortal));
      expect(decoded.durationSec, equals(12));
      expect(decoded.decorativePreset, equals('aurora'));
    });

    test('EphemeralChatMessage round-trips flashCard payload & storage JSON', () {
      final cardJson = const FlashCardData(
        template: FlashCardTemplate.cyberpunkEnergy,
        text: 'Sync Online',
        hologramStyle: HologramStyle.digitalWave,
        durationSec: 10,
      ).toJsonString();

      final msg = EphemeralChatMessage(
        id: 'msg-gt-1',
        senderDeviceId: 'dev-a',
        text: 'Sync Online',
        contentType: ChatContentType.flashCard,
        stickerId: 'presence_miss_you',
        isFlashScreen: true,
        hologramStyle: HologramStyle.digitalWave.name,
        cardDataJson: cardJson,
        displayDurationSec: 10,
        timestamp: 1700000000000,
        isMe: true,
        status: MessageDeliveryStatus.relayed,
      );

      final storageRestored =
          EphemeralChatMessage.fromStorageJson(msg.toStorageJson());
      expect(storageRestored.contentType, equals(ChatContentType.flashCard));
      expect(storageRestored.hologramStyle, equals('digitalWave'));
      expect(storageRestored.displayDurationSec, equals(10));
      expect(storageRestored.cardDataJson, equals(cardJson));

      final encryptedPlaintext = msg.toEncryptedPayloadString();
      final decryptedMsg = EphemeralChatMessage.fromDecryptedPayload(
        id: msg.id,
        senderDeviceId: msg.senderDeviceId,
        decryptedText: encryptedPlaintext,
        timestamp: msg.timestamp,
        isMe: false,
      );
      expect(decryptedMsg.contentType, equals(ChatContentType.flashCard));
      expect(decryptedMsg.hologramStyle, equals('digitalWave'));
      expect(decryptedMsg.displayDurationSec, equals(10));
      expect(decryptedMsg.cardDataJson, equals(cardJson));
      expect(decryptedMsg.isFlashScreen, isTrue);
    });

    test('plain text message remains raw text in toEncryptedPayloadString', () {
      final plain = EphemeralChatMessage(
        senderDeviceId: 'dev-a',
        text: 'Hello',
        timestamp: 1700000000000,
        isMe: true,
      );
      expect(plain.toEncryptedPayloadString(), equals('Hello'));
    });
  });

  group('GhostTouchPreferences', () {
    test('JSON and native sync map round-trip', () {
      const sig = SignatureSticker(
        id: 'sig-1',
        name: 'My Heart',
        pngBase64: 'AAAA',
        createdAt: 1700000000000,
      );
      const prefs = GhostTouchPreferences(
        defaultStyle: HologramStyle.particleAssembly,
        position: OverlayPosition.top,
        displayDurationSec: 15,
        vibrateEnabled: false,
        soundEnabled: true,
        effectIntensity: 0.65,
        reducedMotion: true,
        favoriteStickerIds: ['love_glowing_heart'],
        recentStickerIds: ['cosmic_galaxy_portal'],
        signatureStickers: [sig],
      );

      final restored = GhostTouchPreferences.fromJson(prefs.toJson());
      expect(restored.defaultStyle, equals(HologramStyle.particleAssembly));
      expect(restored.position, equals(OverlayPosition.top));
      expect(restored.displayDurationSec, equals(15));
      expect(restored.vibrateEnabled, isFalse);
      expect(restored.reducedMotion, isTrue);
      expect(restored.effectIntensity, closeTo(0.65, 0.001));
      expect(restored.signatureStickers.length, equals(1));
      expect(restored.signatureStickers.first.id, equals('sig-1'));

      final nativeMap = restored.toNativeSyncMap();
      expect(nativeMap['position'], equals('top'));
      expect(nativeMap['displayDurationSec'], equals(15));
      expect(nativeMap['vibrateEnabled'], isFalse);
      expect(nativeMap['soundEnabled'], isTrue);
      expect(nativeMap['reducedMotion'], isTrue);
    });

    test('GhostReactionMeta resolves distinct verified stickers for all 5 reaction types', () {
      final validIds = GhostStickerCatalog.all.map((e) => e.id).toSet();
      final keys = ['heart', 'mega_heart', 'spark', 'bolt', 'hug'];
      final stickersSeen = <String>{};
      for (final k in keys) {
        final meta = GhostReactionMeta.of(k);
        expect(meta.key, equals(k));
        expect(validIds.contains(meta.stickerId), isTrue,
            reason: 'Sticker ${meta.stickerId} for reaction $k must exist in catalog');
        stickersSeen.add(meta.stickerId);
      }
      expect(stickersSeen.length, equals(5));
    });
  });

  group('Drawing Studio Painters (11 Brushes & 28 Vector Shapes)', () {
    test('all 28 VectorShapeKind shapes and 11 BrushKind brushes paint cleanly', () {
      expect(VectorShapeKind.values.length, equals(28));
      expect(BrushKind.values.length, equals(11));

      for (final kind in VectorShapeKind.values) {
        for (final filled in [false, true]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          DrawingCanvasPainter.paintVectorShape(
            canvas,
            const Offset(64, 64),
            44,
            kind,
            GhostPalette.neonPink,
            secondary: GhostPalette.electricCyan,
            filled: filled,
          );
          final pic = recorder.endRecording();
          pic.dispose();
        }
      }

      for (final brush in BrushKind.values) {
        final stroke = DrawingStroke(
          id: 's_${brush.name}',
          points: const [
            DrawingPoint(offset: Offset(10, 20), pressure: 0.8),
            DrawingPoint(offset: Offset(45, 55), pressure: 1.1),
            DrawingPoint(offset: Offset(90, 35), pressure: 0.9),
          ],
          color: GhostPalette.electricCyan,
          gradientColor: GhostPalette.neonPink,
          strokeWidth: 7.0,
          opacity: 0.85,
          brush: brush,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        DrawingCanvasPainter(
          elements: [
            CanvasElement.fromStroke(stroke),
            CanvasElement.fromStroke(stroke, visible: false),
          ],
          background: CanvasBackgroundKind.auroraDark,
        ).paint(canvas, const Size(160, 160));
        final pic = recorder.endRecording();
        pic.dispose();
      }
    });
  });

  group('Ghost Touch Widgets (RTL & LTR)', () {
    testWidgets('GhostStickerArtwork renders cleanly with animation and disposes',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: GhostPalette.deepSpace,
            body: Center(
              child: GhostStickerArtwork(
                sticker: GhostStickerCatalog.findById('love_glowing_heart'),
                size: 80,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(GhostStickerArtwork), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('HolographicCardRenderer renders RTL Farsi & LTR English cleanly',
        (tester) async {
      const faCard = FlashCardData(
        template: FlashCardTemplate.romanticNeonHeart,
        text: 'سلام عشقم ✨',
        stickerId: 'love_glowing_heart',
        borderEffect: CardBorderEffect.pulse,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: HolographicCardRenderer(data: faCard, isFa: true),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('سلام عشقم ✨'), findsOneWidget);

      const enCard = FlashCardData(
        template: FlashCardTemplate.cyberpunkEnergy,
        text: 'Cyber Signal',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.ltr,
              child: HolographicCardRenderer(data: enCard, isFa: false),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Cyber Signal'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('FloatingHologramExperience renders interactive overlay and handles callbacks',
        (tester) async {
      String? reactedWith;
      String? repliedSticker;
      bool dismissed = false;

      final msg = EphemeralChatMessage(
        senderDeviceId: 'peer-1',
        text: 'Thinking of you',
        contentType: ChatContentType.sticker,
        stickerId: 'presence_miss_you',
        isFlashScreen: true,
        timestamp: 1700000000000,
        isMe: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FloatingHologramExperience(
              message: msg,
              isFa: false,
              hologramStyle: HologramStyle.cosmicPortal,
              onDismiss: () => dismissed = true,
              onQuickReaction: (r) => reactedWith = r,
              onQuickStickerReply: (id) => repliedSticker = id,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 550));

      expect(find.text('Miss You!'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pump(const Duration(milliseconds: 100));
      expect(reactedWith, equals('heart'));

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(dismissed, isTrue);
      expect(repliedSticker, isNull);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('GhostStickerStudio renders cleanly on 390x844 viewport without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GhostStickerStudio(isFa: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('استودیو استیکر هولوگرافیک'), findsOneWidget);
      expect(find.text('شانسی!'), findsOneWidget);
      await tester.tap(find.text('شانسی!'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('UltimateDrawingStudio renders cleanly on 390x844 and switches tabs',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: UltimateDrawingStudio(isFa: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('قلم'), findsOneWidget);
      expect(find.byIcon(Icons.layers_rounded), findsOneWidget);

      await tester.tap(find.text('اشکال'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('${VectorShapeKind.values.length} شکل وکتور درخشان'),
          findsOneWidget);

      await tester.tap(find.text('بوم/فلش'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('فلش'), findsOneWidget);

      final layersBtn = find.byIcon(Icons.layers_rounded);
      await tester.ensureVisible(layersBtn);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(layersBtn);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('مدیریت لایه‌ها'), findsOneWidget);
      Navigator.of(tester.element(find.textContaining('مدیریت لایه‌ها'))).pop();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('HolographicCardDesigner renders cleanly on 390x844 and switches tabs',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: HolographicCardDesigner(isFa: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('طراح کارت پیام هولوگرافیک'), findsOneWidget);
      await tester.tap(find.text('متن و فونت'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('رنگ متن:'), findsOneWidget);
      expect(find.text('نور حاشیه:'), findsOneWidget);

      await tester.tap(find.text('استیکر و قاب'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('تزئین:'), findsOneWidget);

      await tester.tap(find.text('افکت و فلش'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('نمایش هولوگرام فوری'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('HolographicCardRenderer renders all 12 templates x 7 decorative presets',
        (tester) async {
      const presets = [
        'none',
        'sparkles',
        'hearts',
        'orbit',
        'cyberGrid',
        'confetti',
        'bokeh',
      ];
      for (final tpl in FlashCardTemplate.values) {
        for (final preset in presets) {
          final data = FlashCardData(
            template: tpl,
            text: 'Test ${tpl.name}',
            decorativePreset: preset,
            textColorHex: '#A5F3FC',
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: HolographicCardRenderer(
                    data: data,
                    isFa: false,
                    reducedMotion: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}
