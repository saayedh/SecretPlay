import 'package:flutter_test/flutter_test.dart';
import 'package:secretplay/chat/chat_message.dart';
import 'package:secretplay/chat/chat_session.dart';
import 'package:secretplay/security/auto_lock_service.dart';
import 'package:secretplay/cryptography/crypto_service.dart';
import 'package:secretplay/networking/network_mode.dart';
import 'package:secretplay/networking/websocket_client.dart';
import 'package:secretplay/game/controllers/game_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecretPlay Session-Only & Immediate Locking Invariant Tests', () {
    late AutoLockService autoLock;
    late CryptoService crypto;
    late SecretPlayWebSocketClient wsClient;
    late ChatSessionNotifier sessionNotifier;

    setUp(() {
      autoLock = AutoLockService();
      crypto = CryptoService();
      wsClient = SecretPlayWebSocketClient();
      sessionNotifier = ChatSessionNotifier(
        cryptoService: crypto,
        wsClient: wsClient,
        autoLockService: autoLock,
      );
    });

    tearDown(() {
      sessionNotifier.dispose();
      wsClient.dispose();
    });

    test('1. Messages are purely in-memory and cleared on manual clearSession()', () {
      final msg1 = EphemeralChatMessage(
        senderDeviceId: 'dev-1',
        text: 'Hello peer',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isMe: true,
      );

      sessionNotifier.state = [msg1];
      expect(sessionNotifier.state.length, 1);
      expect(sessionNotifier.state.first.text, 'Hello peer');

      // Wiping session
      sessionNotifier.clearSession();
      expect(sessionNotifier.state.isEmpty, true);
    });

    test('2. AutoLock triggers immediate session wipe', () {
      final msg = EphemeralChatMessage(
        senderDeviceId: 'dev-1',
        text: 'Classified payload',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isMe: true,
      );
      sessionNotifier.state = [msg];
      expect(sessionNotifier.state.length, 1);

      // Simulate app backgrounding lock
      autoLock.unlock();
      expect(autoLock.isLocked, false);

      autoLock.triggerLock('test_background');
      expect(autoLock.isLocked, true);
      // Listener clears memory
      expect(sessionNotifier.state.isEmpty, true);
    });

    test('3. Game Controller board matches and level progression', () {
      final game = GameController();
      expect(game.state.score, 0);
      expect(game.state.grid.length, GameController.rows);
      expect(game.state.grid[0].length, GameController.cols);

      // Tap to select tile
      game.onTileTapped(0, 0);
      expect(game.state.selectedTile, isNotNull);
      expect(game.state.selectedTile!.row, 0);
      expect(game.state.selectedTile!.col, 0);

      // Tap adjacent tile to swap
      game.onTileTapped(0, 1);
      expect(game.state.selectedTile, isNull); // Selection cleared after swap
      expect(game.state.movesLeft < 20 + game.state.level * 2, true);
    });

    test('4. Dual-mode NetworkConfig defaults to Cloudflare Free-Tier URL, appends pairToken, and parses Local QR payloads', () {
      const initial = NetworkConfig();
      expect(initial.mode, NetworkMode.cloud);
      expect(initial.activeWsUrl, 'wss://secretplay-relay.enterprise-config-2026.workers.dev/ws');

      final withToken = initial.copyWith(pairToken: 'SP-7492-K9');
      expect(
        withToken.activeWsUrl,
        'wss://secretplay-relay.enterprise-config-2026.workers.dev/ws?token=SP-7492-K9',
      );

      final fromQr = initial.withLocalUrl('{"wsUrl":"ws://192.168.1.44:8787/ws","mode":"local"}');
      expect(fromQr.mode, NetworkMode.local);
      expect(fromQr.localWsHost, '192.168.1.44');
      expect(fromQr.localWsPort, 8787);
      expect(fromQr.activeWsUrl, 'ws://192.168.1.44:8787/ws');
    });
  });
}
