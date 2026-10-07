import 'package:cloud_firestore/cloud_firestore.dart';

class AdminAuditEntry {
  const AdminAuditEntry({
    required this.id,
    required this.actorUid,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.summary,
    this.createdAt,
  });

  final String id;
  final String actorUid;
  final String action;
  final String targetType;
  final String targetId;
  final String summary;
  final DateTime? createdAt;

  factory AdminAuditEntry.fromMap(String id, Map<String, dynamic> map) =>
      AdminAuditEntry(
        id: id,
        actorUid: map['actorUid'] as String? ?? '',
        action: map['action'] as String? ?? '',
        targetType: map['targetType'] as String? ?? '',
        targetId: map['targetId'] as String? ?? '',
        summary: map['summary'] as String? ?? '',
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      );
}
