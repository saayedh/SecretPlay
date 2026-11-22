import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../security/auto_lock_service.dart';
import 'constants.dart';
import 'relay_http_io.dart' if (dart.library.js_interop) 'relay_http_web.dart';

class AppUpdateInfo {
  final String latestVersion;
  final int latestBuild;
  final String downloadUrl;
  final String releaseNotes;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.downloadUrl,
    required this.releaseNotes,
  });
}

class RelayDirectoryService {
  static const MethodChannel _channel = MethodChannel('com.secretplay.app/security');

  /// Registers this device's SecretPlay ID (SP-XXX-XXX) and 64-byte public key in Cloudflare directory
  static Future<void> registerIdentity({
    required String deviceId,
    required String secretNumber,
    required String publicKeyBase64,
  }) async {
    await relayHttpPost(
      '${AppConstants.cloudflareHttpBase}/register',
      {
        'deviceId': deviceId,
        'secretNumber': secretNumber,
        'publicKey': publicKeyBase64,
      },
    );
  }

  /// Looks up a partner's deviceId & publicKey by their SP-XXX-XXX ID so E2EE works even if they are offline!
  static Future<Map<String, String>?> lookupBySecretNumber(String secretNumber) async {
    final clean = secretNumber.trim().toUpperCase();
    if (clean.isEmpty) return null;
    final raw = await relayHttpGet(
      '${AppConstants.cloudflareHttpBase}/lookup?id=${Uri.encodeComponent(clean)}',
    );
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['found'] == true &&
          map['deviceId'] is String &&
          map['publicKey'] is String &&
          (map['publicKey'] as String).isNotEmpty) {
        return {
          'deviceId': map['deviceId'] as String,
          'publicKey': map['publicKey'] as String,
          'secretNumber': (map['secretNumber'] as String?) ?? clean,
        };
      }
    } catch (_) {}
    return null;
  }

  /// Sends an out-of-band push event to a partner's 24/7 Personal Device Inbox DO (/inbox/push)
  /// so heartbeats, disguised online pings, and lock-screen holograms arrive outside the chat screen.
  static Future<bool> pushInboxEvent({
    required String recipientDeviceId,
    required String senderDeviceId,
    required String eventType,
    String? title,
    String? body,
    String? emoji,
    String? colorHex,
    String? mediaBase64,
    int flashSeconds = 7,
    String? roomToken,
    String? hologramStyle,
    String? cardDataJson,
    String? stickerId,
  }) async {
    final target = recipientDeviceId.trim();
    if (target.isEmpty || target == 'peer') return false;
    final payload = <String, dynamic>{
      'recipientDeviceId': target,
      'senderDeviceId': senderDeviceId,
      'eventType': eventType,
      if (title != null && title.isNotEmpty) 'title': title,
      if (body != null && body.isNotEmpty) 'body': body,
      if (emoji != null && emoji.isNotEmpty) 'emoji': emoji,
      if (colorHex != null && colorHex.isNotEmpty) 'colorHex': colorHex,
      if (mediaBase64 != null && mediaBase64.isNotEmpty && mediaBase64.length <= 350000)
        'mediaBase64': mediaBase64,
      'flashSeconds': flashSeconds,
      if (roomToken != null && roomToken.isNotEmpty) 'roomToken': roomToken,
      if (hologramStyle != null && hologramStyle.isNotEmpty) 'hologramStyle': hologramStyle,
      if (cardDataJson != null && cardDataJson.isNotEmpty && cardDataJson.length <= 8000)
        'cardDataJson': cardDataJson,
      if (stickerId != null && stickerId.isNotEmpty) 'stickerId': stickerId,
    };
    final res = await relayHttpPost('${AppConstants.cloudflareHttpBase}/inbox/push', payload);
    return res != null;
  }

  /// Checks Cloudflare /version for newer app updates
  static Future<AppUpdateInfo?> checkForUpdate({bool forceShowIfCurrent = false}) async {
    final raw = await relayHttpGet('${AppConstants.cloudflareHttpBase}/version');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final latestVer = (map['latestVersion'] as String?) ?? AppConstants.appVersion;
      final latestBuild = (map['latestBuild'] as int?) ?? AppConstants.appBuildNumber;
      final url = (map['downloadUrl'] as String?) ?? '';
      final notes = (map['releaseNotes'] as String?) ?? '';

      if (latestBuild > AppConstants.appBuildNumber || forceShowIfCurrent) {
        return AppUpdateInfo(
          latestVersion: latestVer,
          latestBuild: latestBuild,
          downloadUrl: url,
          releaseNotes: notes,
        );
      }
    } catch (_) {}
    return null;
  }

  static bool _isUpdateDialogOpen = false;

  static Future<void> openDownloadUrl(String url) async {
    if (url.isEmpty) return;
    if (kIsWeb) {
      openExternalUrlInBrowser(url);
      await Clipboard.setData(ClipboardData(text: url));
      return;
    }
    try {
      await _channel.invokeMethod('openUrl', {'url': url});
      return;
    } catch (_) {}
    await Clipboard.setData(ClipboardData(text: url));
  }

  static Future<void> downloadAndInstallWithProgress(
    BuildContext context, {
    required String url,
    required bool isFa,
  }) async {
    if (url.isEmpty) return;
    if (kIsWeb) {
      await openDownloadUrl(url);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFa
                  ? 'لینک دانلود در تب جدید باز شد (و کپی گردید).'
                  : 'Download link opened in a new tab!',
            ),
          ),
        );
      }
      return;
    }

    AutoLockService().setTransientOverlayActive(true);
    int progress = 0;
    StateSetter? modalSetState;
    StreamSubscription<int>? sub;

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dCtx) => StatefulBuilder(
          builder: (_, setSt) {
            modalSetState = setSt;
            return Directionality(
              textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
              child: AlertDialog(
                backgroundColor: const Color(0xFF14141E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFF00FFA3)),
                ),
                title: Text(
                  isFa ? 'در حال دانلود آپدیت...' : 'Downloading Update...',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: progress > 0 ? progress / 100.0 : null,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFF00FFA3),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      progress > 0 ? '$progress%' : (isFa ? 'اتصال به سرور دانلود...' : 'Connecting...'),
                      style: const TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    sub = AutoLockService().onUpdateProgress.listen((pct) {
      progress = pct;
      modalSetState?.call(() {});
    });

    bool installed = false;
    try {
      final res = await _channel.invokeMethod<bool>('downloadAndInstallApk', {'url': url});
      installed = res == true;
    } catch (_) {
      installed = false;
    } finally {
      await sub.cancel();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      AutoLockService().setTransientOverlayActive(false);
    }

    if (!installed) {
      await openDownloadUrl(url);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFa
                  ? 'لینک دانلود در مرورگر باز شد؛ پس از دانلود فایل APK را نصب کنید.'
                  : 'Opened download link in browser!',
            ),
          ),
        );
      }
    }
  }

  static Future<void> showUpdateDialogFromPush(
    BuildContext context,
    Map<String, dynamic> payload, {
    required bool isFa,
  }) async {
    final latestVer = (payload['latestVersion'] as String?) ?? AppConstants.appVersion;
    final latestBuild = (payload['latestBuild'] as int?) ?? AppConstants.appBuildNumber;
    final url = (payload['downloadUrl'] as String?) ?? '';
    final notes = (payload['releaseNotes'] as String?) ?? '';
    if (latestBuild <= AppConstants.appBuildNumber || url.isEmpty) return;
    await showUpdateDialog(
      context,
      AppUpdateInfo(
        latestVersion: latestVer,
        latestBuild: latestBuild,
        downloadUrl: url,
        releaseNotes: notes,
      ),
      isFa: isFa,
    );
  }

  static Future<void> checkAndPromptUpdate(
    BuildContext context, {
    required bool isFa,
    bool manualCheck = false,
  }) async {
    final info = await checkForUpdate(forceShowIfCurrent: manualCheck);
    if (info == null || !context.mounted) {
      if (manualCheck && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFa
                  ? 'امکان بررسی آپدیت نبود (وضعیت اینترنت را چک کنید).'
                  : 'Could not reach update server.',
            ),
          ),
        );
      }
      return;
    }

    final isNewer = info.latestBuild > AppConstants.appBuildNumber;
    if (!isNewer && manualCheck) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFa
                ? 'شما در حال استفاده از آخرین نسخه (${AppConstants.appVersion}) هستید ✓'
                : 'You are on the latest version (${AppConstants.appVersion}) ✓',
          ),
        ),
      );
      return;
    }
    if (!isNewer) return;

    await showUpdateDialog(context, info, isFa: isFa);
  }

  static Future<void> showUpdateDialog(
    BuildContext context,
    AppUpdateInfo info, {
    required bool isFa,
  }) async {
    if (_isUpdateDialogOpen || !context.mounted) return;
    _isUpdateDialogOpen = true;
    try {
      await showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            backgroundColor: const Color(0xFF14141E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF00FFA3), width: 1.5),
            ),
            title: Row(
              children: [
                const Icon(Icons.system_update_rounded, color: Color(0xFF00FFA3), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isFa
                        ? 'آپدیت جدید SecretPlay (نسخه ${info.latestVersion})!'
                        : 'SecretPlay Update Available (v${info.latestVersion})!',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.releaseNotes,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 12),
                Text(
                  isFa
                      ? 'نسخه فعلی شما: ${AppConstants.appVersion}  →  نسخه جدید: ${info.latestVersion}'
                      : 'Current: ${AppConstants.appVersion}  →  Latest: ${info.latestVersion}',
                  style: const TextStyle(color: Color(0xFF64D2FF), fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(isFa ? 'بعداً' : 'Later'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  isFa ? 'دانلود و نصب نسخه جدید' : 'Download & Install Update',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FFA3),
                  foregroundColor: Colors.black,
                ),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await downloadAndInstallWithProgress(
                    context,
                    url: info.downloadUrl,
                    isFa: isFa,
                  );
                },
              ),
            ],
          ),
        ),
      );
    } finally {
      _isUpdateDialogOpen = false;
    }
  }
}
