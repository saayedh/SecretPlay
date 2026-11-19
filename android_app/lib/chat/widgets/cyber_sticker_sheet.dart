import 'package:flutter/material.dart';

class CyberSticker {
  final String id;
  final String emoji;
  final String titleFa;
  final String titleEn;
  final Color neonColor;

  const CyberSticker({
    required this.id,
    required this.emoji,
    required this.titleFa,
    required this.titleEn,
    required this.neonColor,
  });
}

class CyberStickerCatalog {
  static const List<CyberSticker> all = [
    CyberSticker(
      id: 'heart_pulse',
      emoji: '❤️‍🔥',
      titleFa: 'دلم برات تنگ شده!',
      titleEn: 'Miss You!',
      neonColor: Color(0xFFFF007A),
    ),
    CyberSticker(
      id: 'wake_up_bolt',
      emoji: '⚡',
      titleFa: 'کجایی؟ بیا آنلاین شو!',
      titleEn: 'Wake Up! Come Online!',
      neonColor: Color(0xFFFFD60A),
    ),
    CyberSticker(
      id: 'cyber_hug',
      emoji: '🫂✨',
      titleFa: 'بغل از راه دور!',
      titleEn: 'Sending a Cyber Hug!',
      neonColor: Color(0xFF00FFA3),
    ),
    CyberSticker(
      id: 'call_me_now',
      emoji: '📞🔥',
      titleFa: 'بیا تماس صوتی!',
      titleEn: 'Call Me Now!',
      neonColor: Color(0xFF00E5FF),
    ),
    CyberSticker(
      id: 'top_secret',
      emoji: '🤫🔐',
      titleFa: 'کاملاً محرمانه!',
      titleEn: 'Top Secret!',
      neonColor: Color(0xFFBF5AF2),
    ),
    CyberSticker(
      id: 'kiss_neon',
      emoji: '💋💫',
      titleFa: 'بوسه نئونی!',
      titleEn: 'Neon Kiss!',
      neonColor: Color(0xFFFF375F),
    ),
    CyberSticker(
      id: 'eyes_on_you',
      emoji: '👀💎',
      titleFa: 'حواسم بهت هست!',
      titleEn: 'Eyes on You!',
      neonColor: Color(0xFF64D2FF),
    ),
    CyberSticker(
      id: 'rocket_go',
      emoji: '🚀🌕',
      titleFa: 'بریم بالا!',
      titleEn: 'To The Moon!',
      neonColor: Color(0xFFFF9F0A),
    ),
  ];

  static CyberSticker findById(String? id) {
    return all.firstWhere(
      (s) => s.id == id,
      orElse: () => all.first,
    );
  }
}

class CyberStickerSelection {
  final CyberSticker sticker;
  final bool flashOnScreen;

  const CyberStickerSelection({
    required this.sticker,
    required this.flashOnScreen,
  });
}

class CyberStickerSheet extends StatefulWidget {
  final bool isFa;

  const CyberStickerSheet({super.key, required this.isFa});

  @override
  State<CyberStickerSheet> createState() => _CyberStickerSheetState();
}

class _CyberStickerSheetState extends State<CyberStickerSheet> {
  bool _flashOnScreen = true;

  @override
  Widget build(BuildContext context) {
    final isFa = widget.isFa;
    return Directionality(
      textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          color: Color(0xFF14141A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isFa ? '✨ استیکرهای هولوگرافیک نئونی' : '✨ Holographic Neon Stickers',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: Color(0xFFFF007A), size: 18),
                    Text(
                      isFa ? 'فلش روی صفحه قفل' : 'Flash Screen',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Switch(
                      value: _flashOnScreen,
                      activeColor: const Color(0xFFFF007A),
                      onChanged: (v) => setState(() => _flashOnScreen = v),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: CyberStickerCatalog.all.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemBuilder: (context, index) {
                final st = CyberStickerCatalog.all[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(context).pop(
                      CyberStickerSelection(
                        sticker: st,
                        flashOnScreen: _flashOnScreen,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: st.neonColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: st.neonColor.withOpacity(0.55)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(st.emoji, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 6),
                        Text(
                          isFa ? st.titleFa : st.titleEn,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
