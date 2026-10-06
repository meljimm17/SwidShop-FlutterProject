import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_model.dart';

/// State of a role-change request.
enum RoleRequestStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const RoleRequestStatus(this.value);

  final String value;

  static RoleRequestStatus fromValue(String? value) =>
      RoleRequestStatus.values.firstWhere(
        (e) => e.value == value,
        orElse: () => RoleRequestStatus.pending,
      );
}

/// A user's request to change role, decided by an admin.
///
/// Lives at `roleRequests/{uid}` (one per user: a new request replaces the
/// previous one), so both sides read it with a plain doc get — no index.
class RoleRequestModel {
  const RoleRequestModel({
    required this.uid,
    required this.currentRole,
    required this.requestedRole,
    this.reason = '',
    this.status = RoleRequestStatus.pending,
    this.adminNote = '',
    this.decidedBy = '',
    this.createdAt,
    this.decidedAt,
  });

  final String uid;
  final UserRole currentRole;
  final UserRole requestedRole;
  final String reason;
  final RoleRequestStatus status;

  /// Optional note from the admin (shown to the user on decline).
  final String adminNote;
  final String decidedBy;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  bool get isPending => status == RoleRequestStatus.pending;

  /// Roles a user may ask for (never admin).
  static const List<UserRole> requestable = [
    UserRole.customer,
    UserRole.both,
  ];

  factory RoleRequestModel.fromMap(String uid, Map<String, dynamic> map) {
    return RoleRequestModel(
      uid: uid,
      currentRole: UserRole.fromValue(map['currentRole'] as String?),
      requestedRole: UserRole.fromValue(map['requestedRole'] as String?),
      reason: map['reason'] as String? ?? '',
      status: RoleRequestStatus.fromValue(map['status'] as String?),
      adminNote: map['adminNote'] as String? ?? '',
      decidedBy: map['decidedBy'] as String? ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      decidedAt: (map['decidedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'currentRole': currentRole.value,
        'requestedRole': requestedRole.value,
        'reason': reason,
        'status': status.value,
        'adminNote': adminNote,
        'decidedBy': decidedBy,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
        'decidedAt': decidedAt != null ? Timestamp.fromDate(decidedAt!) : null,
      };
}
