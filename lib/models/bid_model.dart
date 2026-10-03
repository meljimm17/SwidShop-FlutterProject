import 'package:cloud_firestore/cloud_firestore.dart';

/// A single bid placed on a [ListingModel] of type `bid`.
/// Firestore document id is an auto id.
class BidModel {
  const BidModel({
    required this.bidId,
    required this.listingId,
    required this.bidderId,
    required this.amount,
    this.placedAt,
  });

  final String bidId;
  final String listingId;
  final String bidderId;
  final double amount;
  final DateTime? placedAt;

  factory BidModel.fromMap(String bidId, Map<String, dynamic> map) {
    return BidModel(
      bidId: bidId,
      listingId: map['listingId'] as String? ?? '',
      bidderId: map['bidderId'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      placedAt: (map['placedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'bidId': bidId,
        'listingId': listingId,
        'bidderId': bidderId,
        'amount': amount,
        'placedAt': placedAt != null ? Timestamp.fromDate(placedAt!) : null,
      };

  BidModel copyWith({
    String? bidId,
    String? listingId,
    String? bidderId,
    double? amount,
    DateTime? placedAt,
  }) =>
      BidModel(
        bidId: bidId ?? this.bidId,
        listingId: listingId ?? this.listingId,
        bidderId: bidderId ?? this.bidderId,
        amount: amount ?? this.amount,
        placedAt: placedAt ?? this.placedAt,
      );
}
