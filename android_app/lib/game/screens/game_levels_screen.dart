import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/game_controller.dart';

class GameLevelsScreen extends ConsumerWidget {
  const GameLevelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameNotifier = ref.read(gameProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SECTORS / LEVELS'),
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: 15,
          itemBuilder: (context, index) {
            final level = index + 1;
            final isUnlocked = level <= 5;

            return GestureDetector(
              onTap: isUnlocked
                  ? () {
                      gameNotifier.startLevel(level);
                      Navigator.of(context).pop();
                    }
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  color: isUnlocked
                      ? const Color(0xFF1A1726)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isUnlocked
                        ? const Color(0xFF00FFA3).withOpacity(0.5)
                        : Colors.white12,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isUnlocked ? Icons.play_arrow_rounded : Icons.lock_outline,
                      color: isUnlocked ? const Color(0xFF00FFA3) : Colors.white24,
                      size: 32,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sector $level',
                      style: TextStyle(
                        color: isUnlocked ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
