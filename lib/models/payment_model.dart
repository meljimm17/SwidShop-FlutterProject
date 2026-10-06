import 'package:cloud_firestore/cloud_firestore.dart';

/// `payments.type` values. Partner-ad revenue is NOT a payment record — it
/// comes from `partnerAds.pricePaid` (entered by the admin).
class PaymentType {
  PaymentType._();

  static const String fee = 'fee';
  static const String plan = 'plan';
  static const String photoPack = 'photo_pack';
  static const String boost = 'boost';
  static const String featured = 'featured';

  static const List<String> all = [fee, plan, photoPack, boost, featured];
}

/// A record from the simulated GCash flow (Step 1 — NO real money).
///
/// Written once on payment success, in the same batch that applies the
/// purchase, and never edited/deleted afterwards (rules deny it).
class PaymentModel {
  const PaymentModel({
    this.paymentId = '',
    required this.userId,
    required this.type,
    required this.amount,
    this.label = '',
    this.referenceNo = '',
    this.relatedId = '',
    this.plan = '',
    this.days = 0,
    this.createdAt,
  });

  final String paymentId;
  final String userId;

  /// One of [PaymentType].
  final String type;
  final double amount;

  /// Human line for revenue tables, e.g. "Plus plan · 30 days".
  final String label;

  /// Reference shown in the success pop-up, e.g. `SWD-4F2A9C01`.
  final String referenceNo;

  /// transactionId (fee) / listingId (featured, photo_pack); empty otherwise.
  final String relatedId;

  /// Plan bought ('plus' | 'pro') for type 'plan'; empty otherwise.
  final String plan;

  /// Days bought (plan / boost / featured); 0 otherwise.
  final int days;
  final DateTime? createdAt;

  static int _refCounter = 0;

  /// Generates a demo reference number (no payment provider involved).
  static String newReference() {
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final tail = t.length > 6 ? t.substring(t.length - 6) : t;
    _refCounter = (_refCounter + 1) % 100;
    return 'SWD-${tail.toUpperCase()}${_refCounter.toString().padLeft(2, '0')}';
  }

  /// Deterministic ids let the rules tie a payment to what it pays for.
  static String feeId(String transactionId) => 'fee_$transactionId';
  static String photoPackId(String listingId) => 'photo_pack_$listingId';

  factory PaymentModel.fromMap(String paymentId, Map<String, dynamic> map) {
    return PaymentModel(
      paymentId: paymentId,
      userId: map['userId'] as String? ?? '',
      type: map['type'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      label: map['label'] as String? ?? '',
      referenceNo: map['referenceNo'] as String? ?? '',
      relatedId: map['relatedId'] as String? ?? '',
      plan: map['plan'] as String? ?? '',
      days: (map['days'] as num?)?.toInt() ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'paymentId': paymentId,
        'userId': userId,
        'type': type,
        'amount': amount,
        'label': label,
        'referenceNo': referenceNo,
        'relatedId': relatedId,
        'plan': plan,
        'days': days,
        'createdAt':
            createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      };
}
