import 'package:uuid/uuid.dart';

enum MessageDeliveryStatus {
  sending,
  sent,
  relayed,
  failed,
}

/// Ephemeral In-Memory Chat Message Model
/// Strictly ephemeral: Never serialized to SQLite or shared preferences!
class EphemeralChatMessage {
  final String id;
  final String senderDeviceId;
  final String text;
  final int timestamp;
  final bool isMe;
  final MessageDeliveryStatus status;

  EphemeralChatMessage({
    String? id,
    required this.senderDeviceId,
    required this.text,
    required this.timestamp,
    required this.isMe,
    this.status = MessageDeliveryStatus.sending,
  }) : id = id ?? const Uuid().v4();

  EphemeralChatMessage copyWith({
    MessageDeliveryStatus? status,
  }) {
    return EphemeralChatMessage(
      id: id,
      senderDeviceId: senderDeviceId,
      text: text,
      timestamp: timestamp,
      isMe: isMe,
      status: status ?? this.status,
    );
  }
}
