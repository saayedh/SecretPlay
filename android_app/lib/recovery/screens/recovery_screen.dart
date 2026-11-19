import 'package:flutter/material.dart';
import '../../security/keystore_service.dart';
import '../../cryptography/recovery_crypto.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final KeystoreService _keystore = KeystoreService();
  final RecoveryCryptoService _recoveryCrypto = RecoveryCryptoService();

  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _importVaultController = TextEditingController();

  String? _exportedVaultText;
  String? _statusMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _passphraseController.clear();
    _importVaultController.clear();
    _passphraseController.dispose();
    _importVaultController.dispose();
    super.dispose();
  }

  Future<void> _exportBackup() async {
    final pass = _passphraseController.text.trim();
    if (pass.isEmpty) {
      setState(() => _statusMessage = 'Enter passphrase to encrypt recovery vault.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final devId = await _keystore.getOrCreateDeviceId();
      final myPriv = await _keystore.getIdentityPrivateKey() ?? '';
      final myPub = await _keystore.getIdentityPublicKey() ?? '';
      final peerPub = await _keystore.getPeerPublicKey() ?? '';

      final package = RecoveryPackage(
        deviceId: devId,
        deviceIdentityPrivateKeyBase64: myPriv,
        deviceIdentityPublicKeyBase64: myPub,
        pairedPeerPublicKeyBase64: peerPub,
        requiresReverification: true,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final vault = await _recoveryCrypto.exportEncryptedRecoveryVault(
        package: package,
        passphrase: pass,
      );

      setState(() {
        _exportedVaultText = vault.serialize();
        _statusMessage = 'Recovery vault encrypted with Argon2id + XChaCha20-Poly1305.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Export error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _importBackup() async {
    final rawVault = _importVaultController.text.trim();
    final pass = _passphraseController.text.trim();

    if (rawVault.isEmpty || pass.isEmpty) {
      setState(() => _statusMessage = 'Enter both vault JSON and passphrase to restore.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final vault = EncryptedRecoveryVault.deserialize(rawVault);
      final package = await _recoveryCrypto.importEncryptedRecoveryVault(
        vault: vault,
        passphrase: pass,
      );

      // Restore keys to Keystore
      await _keystore.saveIdentityKeyPair(
        privateKeyBase64: package.deviceIdentityPrivateKeyBase64,
        publicKeyBase64: package.deviceIdentityPublicKeyBase64,
      );

      if (package.pairedPeerPublicKeyBase64.isNotEmpty) {
        await _keystore.savePairedPeer(
          peerDeviceId: 'restored-peer',
          peerPublicKeyBase64: package.pairedPeerPublicKeyBase64,
        );
      }

      setState(() {
        _statusMessage =
            'Identity restored! Re-verification required with peer. Chat history remains zero-storage.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Import error: Invalid passphrase or corrupted vault.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('ENCRYPTED RECOVERY'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF64D2FF).withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF64D2FF)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Account recovery restores only your cryptographic identity keypair and peer public key. In accordance with zero-disk policy, chat messages are NEVER recovered.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _passphraseController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Encryption Passphrase',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('EXPORT ENCRYPTED VAULT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF64D2FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isLoading ? null : _exportBackup,
            ),
            if (_exportedVaultText != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _exportedVaultText!,
                  style: const TextStyle(
                    color: Color(0xFF00FFA3),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            const Divider(color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'IMPORT EXISTING VAULT',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _importVaultController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'Paste encrypted vault JSON here...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.upload),
              label: const Text('RESTORE IDENTITY FROM VAULT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FFA3),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isLoading ? null : _importBackup,
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
