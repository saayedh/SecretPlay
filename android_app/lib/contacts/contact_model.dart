import 'dart:convert';

class SecretContact {
  final String contactId; // Phone-like SecretPlay ID e.g. SP-482-917
  final String alias; // User-assigned display name
  final String roomToken; // Deterministic shared pair token for this 1-on-1 room
  final String? peerDeviceId;
  final String? peerPublicKey;
  final int addedAt;
  final int lastActiveAt;

  const SecretContact({
    required this.contactId,
    required this.alias,
    required this.roomToken,
    this.peerDeviceId,
    this.peerPublicKey,
    required this.addedAt,
    required this.lastActiveAt,
  });

  SecretContact copyWith({
    String? alias,
    String? roomToken,
    String? peerDeviceId,
    String? peerPublicKey,
    int? lastActiveAt,
  }) {
    return SecretContact(
      contactId: contactId,
      alias: alias ?? this.alias,
      roomToken: roomToken ?? this.roomToken,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      peerPublicKey: peerPublicKey ?? this.peerPublicKey,
      addedAt: addedAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'contactId': contactId,
        'alias': alias,
        'roomToken': roomToken,
        if (peerDeviceId != null) 'peerDeviceId': peerDeviceId,
        if (peerPublicKey != null) 'peerPublicKey': peerPublicKey,
        'addedAt': addedAt,
        'lastActiveAt': lastActiveAt,
      };

  factory SecretContact.fromJson(Map<String, dynamic> json) {
    return SecretContact(
      contactId: (json['contactId'] as String? ?? '').trim().toUpperCase(),
      alias: (json['alias'] as String? ?? 'مخاطب امن').trim(),
      roomToken: (json['roomToken'] as String? ?? '').trim().toUpperCase(),
      peerDeviceId: json['peerDeviceId'] as String?,
      peerPublicKey: json['peerPublicKey'] as String?,
      addedAt: (json['addedAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      lastActiveAt: (json['lastActiveAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Derives a permanent, phone-number-like SecretPlay ID (e.g., SP-742-918) from the user's public key or device ID
  static String deriveMySecretNumber(String publicKeyOrDeviceId) {
    final bytes = utf8.encode(publicKeyOrDeviceId.trim());
    int hash1 = 5381;
    int hash2 = 2166136261;
    for (final b in bytes) {
      hash1 = ((hash1 << 5) + hash1 + b) & 0x7FFFFFFF;
      hash2 = ((hash2 ^ b) * 16777619) & 0x7FFFFFFF;
    }
    final part1 = (100 + (hash1 % 900)).toString();
    final part2 = (100 + (hash2 % 900)).toString();
    return 'SP-$part1-$part2';
  }

  /// Normalizes any user input like "742918" or "sp-742-918" into canonical "SP-742-918"
  static String normalizeSecretNumber(String input) {
    final cleaned = input.trim().toUpperCase().replaceAll(' ', '');
    final digitsOnly = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length == 6 && (cleaned.startsWith('SP') || RegExp(r'^[0-9-]+$').hasMatch(cleaned))) {
      return 'SP-${digitsOnly.substring(0, 3)}-${digitsOnly.substring(3, 6)}';
    }
    if (!cleaned.startsWith('SP-') && cleaned.length == 6 && RegExp(r'^[A-Z0-9]+$').hasMatch(cleaned)) {
      return 'SP-${cleaned.substring(0, 3)}-${cleaned.substring(3, 6)}';
    }
    return cleaned;
  }

  /// Computes a deterministic room token for two SecretPlay IDs so both users automatically enter the same room!
  /// Example: Alice (SP-111-222) and Bob (SP-888-999) both compute "PAIR-SP-111-222--SP-888-999"
  static String computePairRoomToken(String mySecretNumber, String peerSecretNumber) {
    final a = normalizeSecretNumber(mySecretNumber);
    final b = normalizeSecretNumber(peerSecretNumber);
    if (a == b) return a;
    // If peerSecretNumber is already an explicit room token (like SP-4829-K7 where part1 has 4 chars), use it directly
    final segments = b.split('-');
    if (segments.length == 3 && segments[1].length == 4) {
      return b;
    }
    final sorted = [a, b]..sort();
    return 'DM-${sorted[0]}-${sorted[1]}';
  }
}
