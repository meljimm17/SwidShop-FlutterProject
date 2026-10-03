import 'package:cloud_firestore/cloud_firestore.dart';

/// Type of an in-app notification.
enum NotificationType {
  outbid('outbid'),
  bidReceived('bidReceived'),
  swapOffer('swapOffer'),
  swapAccepted('swapAccepted'),
  message('message'),
  transactionUpdate('transactionUpdate'),
  rating('rating'),
  system('system');

  const NotificationType(this.value);

  final String value;

  static NotificationType fromValue(String? value) =>
      NotificationType.values.firstWhere(
        (e) => e.value == value,
        orElse: () => NotificationType.system,
      );
}

/// A notification for a user. Lives at `notifications/{uid}/items/{id}`.
/// Firestore document id is an auto id.
class NotificationModel {
  const NotificationModel({
    this.notificationId = '',
    required this.type,
    required this.message,
    this.relatedId = '',
    this.read = false,
    this.createdAt,
  });

  final String notificationId;
  final NotificationType type;
  final String message;

  /// Related document id (listing, transaction, bid, etc.).
  final String relatedId;

  final bool read;
  final DateTime? createdAt;

  factory NotificationModel.fromMap(
    String notificationId,
    Map<String, dynamic> map,
  ) {
    return NotificationModel(
      notificationId: notificationId,
      type: NotificationType.fromValue(map['type'] as String?),
      message: map['message'] as String? ?? '',
      relatedId: map['relatedId'] as String? ?? '',
      read: map['read'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.value,
        'message': message,
        'relatedId': relatedId,
        'read': read,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      };

  NotificationModel copyWith({
    String? notificationId,
    NotificationType? type,
    String? message,
    String? relatedId,
    bool? read,
    DateTime? createdAt,
  }) =>
      NotificationModel(
        notificationId: notificationId ?? this.notificationId,
        type: type ?? this.type,
        message: message ?? this.message,
        relatedId: relatedId ?? this.relatedId,
        read: read ?? this.read,
        createdAt: createdAt ?? this.createdAt,
      );
}
