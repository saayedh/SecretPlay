import 'package:flutter/material.dart';

class GameSettingsScreen extends StatefulWidget {
  const GameSettingsScreen({super.key});

  @override
  State<GameSettingsScreen> createState() => _GameSettingsScreenState();
}

class _GameSettingsScreenState extends State<GameSettingsScreen> {
  bool _sfxEnabled = true;
  bool _hapticsEnabled = true;
  bool _highFps = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ARCADE SETTINGS'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.volume_up, color: Color(0xFF00FFA3)),
                title: const Text('Sound Effects (SFX)'),
                value: _sfxEnabled,
                onChanged: (val) => setState(() => _sfxEnabled = val),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.vibration, color: Color(0xFFFF007A)),
                title: const Text('Haptic Feedback'),
                value: _hapticsEnabled,
                onChanged: (val) => setState(() => _hapticsEnabled = val),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.speed, color: Color(0xFF7928CA)),
                title: const Text('High Refresh Rate (120Hz)'),
                value: _highFps,
                onChanged: (val) => setState(() => _highFps = val),
              ),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Cyber Circuit Arcade Engine v1.0.4',
                style: TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
