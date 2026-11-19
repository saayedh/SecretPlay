import 'dart:convert';
import 'package:uuid/uuid.dart';

enum MessageDeliveryStatus {
  sending,
  sent,
  relayed,
  failed,
}

enum ChatContentType {
  text,
  image,
  drawing,
  sticker,
  voice,
}

/// Ephemeral In-Memory Chat Message Model
/// Strictly ephemeral: Never serialized to SQLite or shared preferences!
class EphemeralChatMessage {
  final String id;
  final String senderDeviceId;
  final String text;
  final ChatContentType contentType;
  final String? mediaBase64;
  final String? stickerId;
  final bool isFlashScreen;
  final int? burnAfterSeconds;
  final int? expiresAtMs;
  final bool isOneTimeVoice;
  final bool isCyberPitch;
  final int? voiceDurationSec;
  final int timestamp;
  final bool isMe;
  final MessageDeliveryStatus status;

  EphemeralChatMessage({
    String? id,
    required this.senderDeviceId,
    required this.text,
    this.contentType = ChatContentType.text,
    this.mediaBase64,
    this.stickerId,
    this.isFlashScreen = false,
    this.burnAfterSeconds,
    this.expiresAtMs,
    this.isOneTimeVoice = false,
    this.isCyberPitch = false,
    this.voiceDurationSec,
    required this.timestamp,
    required this.isMe,
    this.status = MessageDeliveryStatus.sending,
  }) : id = id ?? const Uuid().v4();

  EphemeralChatMessage copyWith({
    MessageDeliveryStatus? status,
    int? expiresAtMs,
  }) {
    return EphemeralChatMessage(
      id: id,
      senderDeviceId: senderDeviceId,
      text: text,
      contentType: contentType,
      mediaBase64: mediaBase64,
      stickerId: stickerId,
      isFlashScreen: isFlashScreen,
      burnAfterSeconds: burnAfterSeconds,
      expiresAtMs: expiresAtMs ?? this.expiresAtMs,
      isOneTimeVoice: isOneTimeVoice,
      isCyberPitch: isCyberPitch,
      voiceDurationSec: voiceDurationSec,
      timestamp: timestamp,
      isMe: isMe,
      status: status ?? this.status,
    );
  }

  /// Packs rich content (image/drawing/sticker/voice/flash/burn timer) into an E2EE JSON envelope
  String toEncryptedPayloadString() {
    if (contentType == ChatContentType.text &&
        !isFlashScreen &&
        (burnAfterSeconds == null || burnAfterSeconds == 0)) {
      return text;
    }
    return jsonEncode({
      '_spRich': 1,
      'kind': contentType.name,
      'text': text,
      if (mediaBase64 != null) 'media': mediaBase64,
      if (stickerId != null) 'sticker': stickerId,
      'flash': isFlashScreen,
      if (burnAfterSeconds != null && burnAfterSeconds! > 0) 'burn': burnAfterSeconds,
      if (isOneTimeVoice) 'oneTime': true,
      if (isCyberPitch) 'cyberPitch': true,
      if (voiceDurationSec != null) 'dur': voiceDurationSec,
    });
  }

  /// Unpacks decrypted E2EE plaintext into rich EphemeralChatMessage
  static EphemeralChatMessage fromDecryptedPayload({
    String? id,
    required String senderDeviceId,
    required String decryptedText,
    required int timestamp,
    required bool isMe,
    MessageDeliveryStatus status = MessageDeliveryStatus.relayed,
  }) {
    if (decryptedText.startsWith('{"_spRich":1')) {
      try {
        final map = jsonDecode(decryptedText) as Map<String, dynamic>;
        final kindStr = map['kind'] as String? ?? 'text';
        final contentType = ChatContentType.values.firstWhere(
          (e) => e.name == kindStr,
          orElse: () => ChatContentType.text,
        );
        final burnSec = map['burn'] as int?;
        final now = DateTime.now().millisecondsSinceEpoch;
        return EphemeralChatMessage(
          id: id,
          senderDeviceId: senderDeviceId,
          text: (map['text'] as String?) ?? '',
          contentType: contentType,
          mediaBase64: map['media'] as String?,
          stickerId: map['sticker'] as String?,
          isFlashScreen: map['flash'] == true,
          burnAfterSeconds: burnSec,
          expiresAtMs: (burnSec != null && burnSec > 0) ? now + (burnSec * 1000) : null,
          isOneTimeVoice: map['oneTime'] == true,
          isCyberPitch: map['cyberPitch'] == true,
          voiceDurationSec: map['dur'] as int?,
          timestamp: timestamp,
          isMe: isMe,
          status: status,
        );
      } catch (_) {}
    }
    return EphemeralChatMessage(
      id: id,
      senderDeviceId: senderDeviceId,
      text: decryptedText,
      timestamp: timestamp,
      isMe: isMe,
      status: status,
    );
  }
}
