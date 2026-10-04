import 'package:cloud_firestore/cloud_firestore.dart';

/// What a report is targeting.
enum ReportTargetType {
  user('user'),
  listing('listing'),

  /// Phase 4.7: a ratings doc (targetId = ratingId).
  rating('rating');

  const ReportTargetType(this.value);

  final String value;

  static ReportTargetType fromValue(String? value) =>
      ReportTargetType.values.firstWhere(
        (e) => e.value == value,
        orElse: () => ReportTargetType.user,
      );
}

/// Moderation status of a report.
enum ReportStatus {
  pending('pending'),
  dismissed('dismissed'),
  warned('warned'),
  suspended('suspended'),
  removed('removed');

  const ReportStatus(this.value);

  final String value;

  static ReportStatus fromValue(String? value) => ReportStatus.values.firstWhere(
        (e) => e.value == value,
        orElse: () => ReportStatus.pending,
      );
}

/// A user-submitted report against a user or listing.
/// Firestore document id is an auto id.
class ReportModel {
  const ReportModel({
    required this.reportId,
    required this.reportedBy,
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.status = ReportStatus.pending,
    this.createdAt,
  });

  final String reportId;
  final String reportedBy;
  final ReportTargetType targetType;
  final String targetId;
  final String reason;
  final ReportStatus status;
  final DateTime? createdAt;

  factory ReportModel.fromMap(String reportId, Map<String, dynamic> map) {
    return ReportModel(
      reportId: reportId,
      reportedBy: map['reportedBy'] as String? ?? '',
      targetType: ReportTargetType.fromValue(map['targetType'] as String?),
      targetId: map['targetId'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
      status: ReportStatus.fromValue(map['status'] as String?),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'reportId': reportId,
        'reportedBy': reportedBy,
        'targetType': targetType.value,
        'targetId': targetId,
        'reason': reason,
        'status': status.value,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      };

  ReportModel copyWith({
    String? reportId,
    String? reportedBy,
    ReportTargetType? targetType,
    String? targetId,
    String? reason,
    ReportStatus? status,
    DateTime? createdAt,
  }) =>
      ReportModel(
        reportId: reportId ?? this.reportId,
        reportedBy: reportedBy ?? this.reportedBy,
        targetType: targetType ?? this.targetType,
        targetId: targetId ?? this.targetId,
        reason: reason ?? this.reason,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
}
