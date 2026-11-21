import 'package:flutter/material.dart';

class CyberSticker {
  final String id;
  final String emoji;
  final String titleFa;
  final String titleEn;
  final String category; // 'love' | 'fun' | 'quick' | 'cyber'
  final Color neonColor;

  const CyberSticker({
    required this.id,
    required this.emoji,
    required this.titleFa,
    required this.titleEn,
    required this.category,
    required this.neonColor,
  });
}

class CyberStickerCatalog {
  static const List<CyberSticker> all = [
    // ❤️ Love & Mood (9)
    CyberSticker(
      id: 'heart_pulse',
      emoji: '❤️‍🔥',
      titleFa: 'دلم برات تنگ شده!',
      titleEn: 'Miss You!',
      category: 'love',
      neonColor: Color(0xFFFF007A),
    ),
    CyberSticker(
      id: 'kiss_neon',
      emoji: '💋💫',
      titleFa: 'بوسه نئونی!',
      titleEn: 'Neon Kiss!',
      category: 'love',
      neonColor: Color(0xFFFF375F),
    ),
    CyberSticker(
      id: 'cyber_hug',
      emoji: '🫂✨',
      titleFa: 'بغل از راه دور!',
      titleEn: 'Cyber Hug!',
      category: 'love',
      neonColor: Color(0xFF00FFA3),
    ),
    CyberSticker(
      id: 'love_you',
      emoji: '🥰💖',
      titleFa: 'عاشقتم!',
      titleEn: 'Love You!',
      category: 'love',
      neonColor: Color(0xFFFF4D94),
    ),
    CyberSticker(
      id: 'rose_glow',
      emoji: '🌹✨',
      titleFa: 'تقدیم به تو!',
      titleEn: 'For You!',
      category: 'love',
      neonColor: Color(0xFFFF2A5F),
    ),
    CyberSticker(
      id: 'good_night',
      emoji: '🌙💫',
      titleFa: 'شب بخیر عزیزم',
      titleEn: 'Good Night',
      category: 'love',
      neonColor: Color(0xFF9D4EDD),
    ),
    CyberSticker(
      id: 'good_morning',
      emoji: '☀️💛',
      titleFa: 'صبح بخیر!',
      titleEn: 'Good Morning!',
      category: 'love',
      neonColor: Color(0xFFFFD60A),
    ),
    CyberSticker(
      id: 'heart_hands',
      emoji: '🫶🌟',
      titleFa: 'بهترینی!',
      titleEn: 'You Are The Best!',
      category: 'love',
      neonColor: Color(0xFFFF70A6),
    ),
    CyberSticker(
      id: 'please_eyes',
      emoji: '🥺💜',
      titleFa: 'لطفاً...',
      titleEn: 'Pretty Please!',
      category: 'love',
      neonColor: Color(0xFFBF5AF2),
    ),

    // 😂 Fun & Reactions (9)
    CyberSticker(
      id: 'lol_dead',
      emoji: '😂💀',
      titleFa: 'ترکیدم از خنده!',
      titleEn: 'LMAO!',
      category: 'fun',
      neonColor: Color(0xFFFFD60A),
    ),
    CyberSticker(
      id: 'cool_vibe',
      emoji: '😎🔥',
      titleFa: 'عالیه، خفنه!',
      titleEn: 'Too Cool!',
      category: 'fun',
      neonColor: Color(0xFFFF9F0A),
    ),
    CyberSticker(
      id: 'mind_blown',
      emoji: '🤯💥',
      titleFa: 'مغزم سوت کشید!',
      titleEn: 'Mind Blown!',
      category: 'fun',
      neonColor: Color(0xFFFF453A),
    ),
    CyberSticker(
      id: 'star_struck',
      emoji: '🤩✨',
      titleFa: 'فوق‌العاده!',
      titleEn: 'Amazing!',
      category: 'fun',
      neonColor: Color(0xFF00E5FF),
    ),
    CyberSticker(
      id: 'salute_boss',
      emoji: '🫡🎖️',
      titleFa: 'چشم قربان!',
      titleEn: 'Aye Captain!',
      category: 'fun',
      neonColor: Color(0xFF00FFA3),
    ),
    CyberSticker(
      id: 'top_secret',
      emoji: '🤫🔐',
      titleFa: 'کاملاً محرمانه!',
      titleEn: 'Top Secret!',
      category: 'fun',
      neonColor: Color(0xFFBF5AF2),
    ),
    CyberSticker(
      id: 'eyes_on_you',
      emoji: '👀💎',
      titleFa: 'حواسم بهت هست!',
      titleEn: 'Eyes on You!',
      category: 'fun',
      neonColor: Color(0xFF64D2FF),
    ),
    CyberSticker(
      id: 'party_boom',
      emoji: '🎉🎊',
      titleFa: 'مبارکه! هورا!',
      titleEn: 'Celebrate!',
      category: 'fun',
      neonColor: Color(0xFFFF007A),
    ),
    CyberSticker(
      id: 'upside_down',
      emoji: '🙃⚡',
      titleFa: 'بی‌خیال بابا!',
      titleEn: 'Whatever!',
      category: 'fun',
      neonColor: Color(0xFF38BDF8),
    ),

    // ⚡ Quick & Urgent (9)
    CyberSticker(
      id: 'wake_up_bolt',
      emoji: '⚡',
      titleFa: 'کجایی؟ بیا آنلاین!',
      titleEn: 'Come Online!',
      category: 'quick',
      neonColor: Color(0xFFFFD60A),
    ),
    CyberSticker(
      id: 'call_me_now',
      emoji: '📞🔥',
      titleFa: 'بیا تماس صوتی!',
      titleEn: 'Voice Call Now!',
      category: 'quick',
      neonColor: Color(0xFF00E5FF),
    ),
    CyberSticker(
      id: 'video_call_now',
      emoji: '🎥✨',
      titleFa: 'بیا تماس تصویری!',
      titleEn: 'Video Call!',
      category: 'quick',
      neonColor: Color(0xFF00FFA3),
    ),
    CyberSticker(
      id: 'on_my_way',
      emoji: '🏃‍♂️💨',
      titleFa: 'الان میام!',
      titleEn: 'On My Way!',
      category: 'quick',
      neonColor: Color(0xFF64D2FF),
    ),
    CyberSticker(
      id: 'wait_sec',
      emoji: '⏰🚨',
      titleFa: 'یه لحظه صبر کن',
      titleEn: 'Wait a Sec!',
      category: 'quick',
      neonColor: Color(0xFFFF9F0A),
    ),
    CyberSticker(
      id: 'ok_done',
      emoji: '✅💚',
      titleFa: 'حله، انجام شد!',
      titleEn: 'Done & OK!',
      category: 'quick',
      neonColor: Color(0xFF00FFA3),
    ),
    CyberSticker(
      id: 'no_way',
      emoji: '❌🛑',
      titleFa: 'اصلاً و ابداً!',
      titleEn: 'No Way!',
      category: 'quick',
      neonColor: Color(0xFFFF453A),
    ),
    CyberSticker(
      id: 'thanks_lot',
      emoji: '🙏✨',
      titleFa: 'دمت گرم، مرسی!',
      titleEn: 'Thank You!',
      category: 'quick',
      neonColor: Color(0xFFC084FC),
    ),
    CyberSticker(
      id: 'thumbs_up',
      emoji: '👍⚡',
      titleFa: 'ایول!',
      titleEn: 'Awesome!',
      category: 'quick',
      neonColor: Color(0xFF00E5FF),
    ),

    // 🚀 Cyber & Vibes (9)
    CyberSticker(
      id: 'rocket_go',
      emoji: '🚀🌕',
      titleFa: 'بریم بالا!',
      titleEn: 'To The Moon!',
      category: 'cyber',
      neonColor: Color(0xFFFF9F0A),
    ),
    CyberSticker(
      id: 'gaming_time',
      emoji: '👾🎮',
      titleFa: 'وقت بازیه!',
      titleEn: 'Game Time!',
      category: 'cyber',
      neonColor: Color(0xFF9D4EDD),
    ),
    CyberSticker(
      id: 'shield_safe',
      emoji: '🛡️🔐',
      titleFa: 'امن و امانه!',
      titleEn: '100% Secure!',
      category: 'cyber',
      neonColor: Color(0xFF00FFA3),
    ),
    CyberSticker(
      id: 'diamond_vip',
      emoji: '💎❄️',
      titleFa: 'لاکچری و خاص!',
      titleEn: 'VIP Diamond!',
      category: 'cyber',
      neonColor: Color(0xFF38BDF8),
    ),
    CyberSticker(
      id: 'king_queen',
      emoji: '👑🔥',
      titleFa: 'سلطان!',
      titleEn: 'Royalty!',
      category: 'cyber',
      neonColor: Color(0xFFFFD60A),
    ),
    CyberSticker(
      id: 'music_chill',
      emoji: '🎧🌌',
      titleFa: 'موزیک و آرامش',
      titleEn: 'Chill Vibes',
      category: 'cyber',
      neonColor: Color(0xFFE879F9),
    ),
    CyberSticker(
      id: 'coffee_break',
      emoji: '☕🌙',
      titleFa: 'بریم قهوه؟',
      titleEn: 'Coffee Break?',
      category: 'cyber',
      neonColor: Color(0xFFF59E0B),
    ),
    CyberSticker(
      id: 'trophy_win',
      emoji: '🏆⚡',
      titleFa: 'بردیم!',
      titleEn: 'Victory!',
      category: 'cyber',
      neonColor: Color(0xFF00FFA3),
    ),
    CyberSticker(
      id: 'ghost_stealth',
      emoji: '👻🕶️',
      titleFa: 'حالت مخفی!',
      titleEn: 'Stealth Mode!',
      category: 'cyber',
      neonColor: Color(0xFF94A3B8),
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
  bool _flashOnScreen = false;
  String _selectedCategory = 'all';

  @override
  Widget build(BuildContext context) {
    final isFa = widget.isFa;
    final categories = [
      ('all', isFa ? '✨ همه (۳۶)' : '✨ All (36)'),
      ('love', isFa ? '❤️ احساسی' : '❤️ Love'),
      ('fun', isFa ? '😂 خنده' : '😂 Fun'),
      ('quick', isFa ? '⚡ فوری' : '⚡ Quick'),
      ('cyber', isFa ? '🚀 سایبری' : '🚀 Cyber'),
    ];
    final items = _selectedCategory == 'all'
        ? CyberStickerCatalog.all
        : CyberStickerCatalog.all.where((s) => s.category == _selectedCategory).toList();

    return Directionality(
      textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.62,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF15192B), Color(0xFF0B0E18)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Color(0xFF00FFA3), width: 1.5)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isFa ? '✨ استیکرهای هولوگرافیک' : '✨ Holographic Stickers',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: Color(0xFFFF007A), size: 17),
                    Text(
                      isFa ? 'فلش صفحه' : 'Flash',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
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
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, idx) {
                  final (key, label) = categories[idx];
                  final active = _selectedCategory == key;
                  return ChoiceChip(
                    label: Text(
                      label,
                      style: TextStyle(
                        color: active ? Colors.black : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: active,
                    selectedColor: const Color(0xFF00FFA3),
                    backgroundColor: Colors.white.withOpacity(0.06),
                    side: BorderSide(
                      color: active ? const Color(0xFF00FFA3) : Colors.white12,
                    ),
                    onSelected: (_) => setState(() => _selectedCategory = key),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.84,
                ),
                itemBuilder: (context, index) {
                  final st = items[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
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
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            st.neonColor.withOpacity(0.20),
                            st.neonColor.withOpacity(0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: st.neonColor.withOpacity(0.5)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(st.emoji, style: const TextStyle(fontSize: 28)),
                          const SizedBox(height: 5),
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
            ),
          ],
        ),
      ),
    );
  }
}
