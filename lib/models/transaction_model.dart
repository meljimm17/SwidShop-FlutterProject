import 'package:cloud_firestore/cloud_firestore.dart';

import 'listing_model.dart' show ListingType;

/// Lifecycle status of a transaction.
enum TransactionStatus {
  pending('pending'),
  ongoing('ongoing'),
  completed('completed'),
  cancelled('cancelled'),
  disputed('disputed');

  const TransactionStatus(this.value);

  final String value;

  static TransactionStatus fromValue(String? value) =>
      TransactionStatus.values.firstWhere(
        (e) => e.value == value,
        orElse: () => TransactionStatus.pending,
      );
}

/// A completed/ongoing deal between a buyer and seller.
/// Firestore document id is an auto id.
///
/// The chat thread for a transaction lives at
/// `chats/{transactionId}/messages`.
class TransactionModel {
  const TransactionModel({
    required this.transactionId,
    required this.listingId,
    required this.buyerId,
    required this.sellerId,
    this.type = ListingType.buyNow,
    this.amount = 0,
    this.listingTitle = '',
    this.listingImage = '',
    this.offerId = '',
    this.swapItemTitle = '',
    this.status = TransactionStatus.pending,
    this.createdAt,
    this.feeRate = 0,
    this.feeAmount = 0,
    this.feeStatus = 'none',
    this.feeDueAt,
    this.paidAt,
  });

  final String transactionId;
  final String listingId;
  final String buyerId;
  final String sellerId;
  final ListingType type;
  final double amount;

  /// Snapshot of the listing at deal time, for history rows / chat header.
  final String listingTitle;
  final String listingImage;

  /// Swap deals: the accepted swapOffers doc id.
  final String offerId;

  /// Swap deals: title of the item the buyer gave in exchange.
  final String swapItemTitle;

  final TransactionStatus status;
  final DateTime? createdAt;

  /// Platform commission (demo monetization): the seller plan rate stamped
  /// at deal time, the peso amount, and its payment state.
  /// feeStatus: 'none' (swaps / legacy) | 'unpaid' | 'paid' | 'void'.
  final double feeRate;
  final double feeAmount;
  final String feeStatus;
  final DateTime? feeDueAt;
  final DateTime? paidAt;

  /// True when this deal carries an outstanding platform fee.
  bool get feeUnpaid => feeStatus == 'unpaid';

  /// True when the fee is unpaid AND past its due date.
  bool get feeOverdue =>
      feeStatus == 'unpaid' &&
      feeDueAt != null &&
      !feeDueAt!.isAfter(DateTime.now());

  /// Short human order number, e.g. `SW-4F2A9C`.
  String get orderNumber {
    final clean = transactionId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final tail = clean.length > 6 ? clean.substring(clean.length - 6) : clean;
    return 'SW-${tail.toUpperCase()}';
  }

  factory TransactionModel.fromMap(
    String transactionId,
    Map<String, dynamic> map,
  ) {
    return TransactionModel(
      transactionId: transactionId,
      listingId: map['listingId'] as String? ?? '',
      buyerId: map['buyerId'] as String? ?? '',
      sellerId: map['sellerId'] as String? ?? '',
      type: ListingType.fromValue(map['type'] as String?),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      listingTitle: map['listingTitle'] as String? ?? '',
      listingImage: map['listingImage'] as String? ?? '',
      offerId: map['offerId'] as String? ?? '',
      swapItemTitle: map['swapItemTitle'] as String? ?? '',
      status: TransactionStatus.fromValue(map['status'] as String?),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      feeRate: (map['feeRate'] as num?)?.toDouble() ?? 0,
      feeAmount: (map['feeAmount'] as num?)?.toDouble() ?? 0,
      feeStatus: map['feeStatus'] as String? ?? 'none',
      feeDueAt: (map['feeDueAt'] as Timestamp?)?.toDate(),
      paidAt: (map['paidAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'transactionId': transactionId,
        'listingId': listingId,
        'buyerId': buyerId,
        'sellerId': sellerId,
        'type': type.value,
        'amount': amount,
        'listingTitle': listingTitle,
        'listingImage': listingImage,
        'offerId': offerId,
        'swapItemTitle': swapItemTitle,
        'status': status.value,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
        'feeRate': feeRate,
        'feeAmount': feeAmount,
        'feeStatus': feeStatus,
        'feeDueAt': feeDueAt != null ? Timestamp.fromDate(feeDueAt!) : null,
        'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
      };

  TransactionModel copyWith({
    String? transactionId,
    String? listingId,
    String? buyerId,
    String? sellerId,
    ListingType? type,
    double? amount,
    String? listingTitle,
    String? listingImage,
    String? offerId,
    String? swapItemTitle,
    TransactionStatus? status,
    DateTime? createdAt,
    double? feeRate,
    double? feeAmount,
    String? feeStatus,
    DateTime? feeDueAt,
    DateTime? paidAt,
  }) =>
      TransactionModel(
        transactionId: transactionId ?? this.transactionId,
        listingId: listingId ?? this.listingId,
        buyerId: buyerId ?? this.buyerId,
        sellerId: sellerId ?? this.sellerId,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        listingTitle: listingTitle ?? this.listingTitle,
        listingImage: listingImage ?? this.listingImage,
        offerId: offerId ?? this.offerId,
        swapItemTitle: swapItemTitle ?? this.swapItemTitle,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        feeRate: feeRate ?? this.feeRate,
        feeAmount: feeAmount ?? this.feeAmount,
        feeStatus: feeStatus ?? this.feeStatus,
        feeDueAt: feeDueAt ?? this.feeDueAt,
        paidAt: paidAt ?? this.paidAt,
      );
}
