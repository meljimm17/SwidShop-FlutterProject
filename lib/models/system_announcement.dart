import 'package:cloud_firestore/cloud_firestore.dart';

class SystemAnnouncement {
  const SystemAnnouncement({
    this.enabled = false,
    this.message = '',
    this.updatedAt,
  });

  final bool enabled;
  final String message;
  final DateTime? updatedAt;

  factory SystemAnnouncement.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SystemAnnouncement();
    return SystemAnnouncement(
      enabled: map['announcementEnabled'] as bool? ?? false,
      message: map['announcementMessage'] as String? ?? '',
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
