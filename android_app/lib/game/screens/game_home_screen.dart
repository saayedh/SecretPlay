import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/game_controller.dart';
import '../models/game_board.dart';
import 'game_levels_screen.dart';
import 'game_settings_screen.dart';
import '../../authentication/screens/private_access_screen.dart';

class GameHomeScreen extends ConsumerStatefulWidget {
  const GameHomeScreen({super.key});

  @override
  ConsumerState<GameHomeScreen> createState() => _GameHomeScreenState();
}

class _GameHomeScreenState extends ConsumerState<GameHomeScreen> {
  int _trophyTapCount = 0;
  DateTime? _lastTapTime;

  void _onTrophyTapped() {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    if (_lastTapTime == null || now.difference(_lastTapTime!).inMilliseconds > 900) {
      _trophyTapCount = 1;
    } else {
      _trophyTapCount++;
    }
    _lastTapTime = now;

    if (_trophyTapCount >= 3) {
      _trophyTapCount = 0;
      _openPrivateGateway();
    }
  }

  void _openPrivateGateway() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, animation, __) => const PrivateAccessScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  List<Color> _getGemGradient(GemType type) {
    switch (type) {
      case GemType.cyan:
        return [const Color(0xFF00E5FF), const Color(0xFF0077FF)];
      case GemType.neonPink:
        return [const Color(0xFFFF2A85), const Color(0xFFFF0055)];
      case GemType.electricGreen:
        return [const Color(0xFF00FFA3), const Color(0xFF00B86B)];
      case GemType.amber:
        return [const Color(0xFFFFD60A), const Color(0xFFFF8800)];
      case GemType.purple:
        return [const Color(0xFFE040FB), const Color(0xFF7C4DFF)];
    }
  }

  IconData _getGemIcon(GemType type) {
    switch (type) {
      case GemType.cyan:
        return Icons.diamond_rounded;
      case GemType.neonPink:
        return Icons.favorite_rounded;
      case GemType.electricGreen:
        return Icons.bolt_rounded;
      case GemType.amber:
        return Icons.hexagon_rounded;
      case GemType.purple:
        return Icons.auto_awesome_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameProvider);
    final gameNotifier = ref.read(gameProvider.notifier);
    final progress = (gameState.score / (gameState.targetScore > 0 ? gameState.targetScore : 1))
        .clamp(0.0, 1.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.6),
            radius: 1.2,
            colors: [Color(0xFF161B33), Color(0xFF07080D)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Sleek Arcade Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: _onTrophyTapped,
                      onLongPress: _openPrivateGateway,
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00FFA3), Color(0xFF00E5FF)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00FFA3).withOpacity(0.35),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.gamepad_rounded, color: Colors.black, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CYBER CIRCUIT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              Text(
                                'SECTOR ${gameState.level.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  color: Color(0xFF00E5FF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Secret Trophy Trigger
                    GestureDetector(
                      onTap: _onTrophyTapped,
                      onLongPress: _openPrivateGateway,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.35)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD700), size: 20),
                            SizedBox(width: 4),
                            Text(
                              'PRO',
                              style: TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 11,
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

              // Score & Progress HUD
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'SCORE',
                            '${gameState.score}',
                            const Color(0xFF00FFA3),
                            Icons.stars_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildStatCard(
                            'MOVES',
                            '${gameState.movesLeft}',
                            const Color(0xFFFF2A85),
                            Icons.bolt_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildStatCard(
                            'TARGET',
                            '${gameState.targetScore}',
                            const Color(0xFF00E5FF),
                            Icons.flag_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 7,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00FFA3)),
                      ),
                    ),
                  ],
                ),
              ),

              // 7x7 Glowing Game Grid
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: Container(
                      margin: const EdgeInsets.all(14),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E111D).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withOpacity(0.08),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: GameController.cols,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemCount: GameController.rows * GameController.cols,
                        itemBuilder: (context, index) {
                          final r = index ~/ GameController.cols;
                          final c = index % GameController.cols;
                          if (r >= gameState.grid.length || c >= gameState.grid[r].length) {
                            return const SizedBox();
                          }
                          final tile = gameState.grid[r][c];
                          final isSelected = gameState.selectedTile?.row == r &&
                              gameState.selectedTile?.col == c;
                          final grad = _getGemGradient(tile.type);

                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              gameNotifier.onTileTapped(r, c);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              transform: isSelected
                                  ? (Matrix4.identity()..scale(1.08))
                                  : Matrix4.identity(),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    grad[0].withOpacity(isSelected ? 0.55 : 0.22),
                                    grad[1].withOpacity(isSelected ? 0.38 : 0.10),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: isSelected ? Colors.white : grad[0].withOpacity(0.55),
                                  width: isSelected ? 2.2 : 1.0,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: grad[0].withOpacity(0.65),
                                          blurRadius: 12,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Icon(
                                  _getGemIcon(tile.type),
                                  color: grad[0],
                                  size: 22,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Action Dock
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131624),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.grid_view_rounded, size: 26, color: Colors.white70),
                        tooltip: 'Sectors',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const GameLevelsScreen()),
                          );
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text('NEW GAME'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FFA3),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => gameNotifier.startLevel(gameState.level),
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, size: 26, color: Colors.white70),
                        tooltip: 'Settings',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const GameSettingsScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF131624),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
