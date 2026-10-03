import 'package:cloud_firestore/cloud_firestore.dart';

/// A rating left after a transaction. Firestore document id is an auto id.
class RatingModel {
  const RatingModel({
    required this.ratingId,
    required this.raterId,
    required this.ratedUserId,
    required this.transactionId,
    required this.stars,
    this.comment = '',
    this.createdAt,
  });

  final String ratingId;
  final String raterId;
  final String ratedUserId;
  final String transactionId;

  /// Integer 1–5.
  final int stars;

  final String comment;
  final DateTime? createdAt;

  factory RatingModel.fromMap(String ratingId, Map<String, dynamic> map) {
    return RatingModel(
      ratingId: ratingId,
      raterId: map['raterId'] as String? ?? '',
      ratedUserId: map['ratedUserId'] as String? ?? '',
      transactionId: map['transactionId'] as String? ?? '',
      stars: (map['stars'] as num?)?.toInt() ?? 0,
      comment: map['comment'] as String? ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'ratingId': ratingId,
        'raterId': raterId,
        'ratedUserId': ratedUserId,
        'transactionId': transactionId,
        'stars': stars,
        'comment': comment,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      };

  RatingModel copyWith({
    String? ratingId,
    String? raterId,
    String? ratedUserId,
    String? transactionId,
    int? stars,
    String? comment,
    DateTime? createdAt,
  }) =>
      RatingModel(
        ratingId: ratingId ?? this.ratingId,
        raterId: raterId ?? this.raterId,
        ratedUserId: ratedUserId ?? this.ratedUserId,
        transactionId: transactionId ?? this.transactionId,
        stars: stars ?? this.stars,
        comment: comment ?? this.comment,
        createdAt: createdAt ?? this.createdAt,
      );
}
