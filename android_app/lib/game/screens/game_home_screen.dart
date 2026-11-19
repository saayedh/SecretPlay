import 'package:flutter/material.dart';
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
    final now = DateTime.now();
    if (_lastTapTime == null || now.difference(_lastTapTime!).inMilliseconds > 800) {
      _trophyTapCount = 1;
    } else {
      _trophyTapCount++;
    }
    _lastTapTime = now;

    // Secret trigger: 3 rapid taps or long press opens private access screen
    if (_trophyTapCount >= 3) {
      _trophyTapCount = 0;
      _openPrivateGateway();
    }
  }

  void _openPrivateGateway() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const PrivateAccessScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Color _getGemColor(GemType type) {
    switch (type) {
      case GemType.cyan:
        return const Color(0xFF00E5FF);
      case GemType.neonPink:
        return const Color(0xFFFF1744);
      case GemType.electricGreen:
        return const Color(0xFF00E676);
      case GemType.amber:
        return const Color(0xFFFFAB00);
      case GemType.purple:
        return const Color(0xFFD500F9);
    }
  }

  IconData _getGemIcon(GemType type) {
    switch (type) {
      case GemType.cyan:
        return Icons.diamond_outlined;
      case GemType.neonPink:
        return Icons.hexagon_outlined;
      case GemType.electricGreen:
        return Icons.square_outlined;
      case GemType.amber:
        return Icons.circle_outlined;
      case GemType.purple:
        return Icons.star_border_purple500_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameProvider);
    final gameNotifier = ref.read(gameProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onTrophyTapped,
          onLongPress: _openPrivateGateway,
          child: const Text('CYBER CIRCUIT'),
        ),
        actions: [
          // Secret trigger disguised as Trophy Icon
          GestureDetector(
            onTap: _onTrophyTapped,
            onLongPress: _openPrivateGateway,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emoji_events_outlined,
                  color: Color(0xFFFFD700),
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Score Board
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatCard('SCORE', '${gameState.score}', const Color(0xFF00FFA3)),
                  _buildStatCard('MOVES', '${gameState.movesLeft}', const Color(0xFFFF007A)),
                  _buildStatCard('TARGET', '${gameState.targetScore}', const Color(0xFF7928CA)),
                ],
              ),
            ),

            // Game Grid Board
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13111C),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
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

                        return GestureDetector(
                          onTap: () => gameNotifier.onTileTapped(r, c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: _getGemColor(tile.type).withOpacity(isSelected ? 0.4 : 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : _getGemColor(tile.type).withOpacity(0.6),
                                width: isSelected ? 2.5 : 1.2,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: _getGemColor(tile.type).withOpacity(0.6),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      )
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              _getGemIcon(tile.type),
                              color: _getGemColor(tile.type),
                              size: 24,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Navigation Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.grid_view_rounded, size: 28),
                    color: Colors.white70,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const GameLevelsScreen()),
                      );
                    },
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('RESTART'),
                    onPressed: () => gameNotifier.startLevel(gameState.level),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, size: 28),
                    color: Colors.white70,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const GameSettingsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF13111C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
