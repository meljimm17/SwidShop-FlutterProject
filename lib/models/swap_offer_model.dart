import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a swap offer.
enum SwapOfferStatus {
  pending('pending'),
  accepted('accepted'),
  declined('declined');

  const SwapOfferStatus(this.value);

  final String value;

  static SwapOfferStatus fromValue(String? value) =>
      SwapOfferStatus.values.firstWhere(
        (e) => e.value == value,
        orElse: () => SwapOfferStatus.pending,
      );
}

/// An offer to swap something for a listing. Firestore document id is an
/// auto id. The offered item is EITHER one of the offerer's listings
/// ([offeredItemId]) OR a photo offer straight from their phone
/// ([offeredTitle] + [offeredImages], no listing needed).
class SwapOfferModel {
  const SwapOfferModel({
    required this.offerId,
    required this.listingId,
    required this.offeredById,
    this.offeredItemId = '',
    this.offeredTitle = '',
    this.offeredImages = const [],
    this.sellerId = '',
    this.message = '',
    this.status = SwapOfferStatus.pending,
    this.createdAt,
  });

  final String offerId;

  /// The listing being requested (the target).
  final String listingId;

  /// The user making the offer.
  final String offeredById;

  /// The listing the offerer is giving up in exchange ('' for a photo
  /// offer).
  final String offeredItemId;

  /// Photo offer: what the item is, e.g. "Uniqlo linen shirt, size M".
  final String offeredTitle;

  /// Photo offer: Cloudinary secure_urls of the item (1–4).
  final List<String> offeredImages;

  /// True when the item is shown by photos instead of a listing.
  bool get isPhotoOffer => offeredItemId.isEmpty && offeredImages.isNotEmpty;

  /// Owner of [listingId] (denormalised so sellers can query their offers
  /// with a single equality filter).
  final String sellerId;

  /// Optional note from the offerer.
  final String message;

  final SwapOfferStatus status;
  final DateTime? createdAt;

  factory SwapOfferModel.fromMap(String offerId, Map<String, dynamic> map) {
    return SwapOfferModel(
      offerId: offerId,
      listingId: map['listingId'] as String? ?? '',
      offeredById: map['offeredById'] as String? ?? '',
      offeredItemId: map['offeredItemId'] as String? ?? '',
      offeredTitle: map['offeredTitle'] as String? ?? '',
      offeredImages: (map['offeredImages'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sellerId: map['sellerId'] as String? ?? '',
      message: map['message'] as String? ?? '',
      status: SwapOfferStatus.fromValue(map['status'] as String?),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'offerId': offerId,
        'listingId': listingId,
        'offeredById': offeredById,
        'offeredItemId': offeredItemId,
        'offeredTitle': offeredTitle,
        'offeredImages': offeredImages,
        'sellerId': sellerId,
        'message': message,
        'status': status.value,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      };

  SwapOfferModel copyWith({
    String? offerId,
    String? listingId,
    String? offeredById,
    String? offeredItemId,
    String? offeredTitle,
    List<String>? offeredImages,
    String? sellerId,
    String? message,
    SwapOfferStatus? status,
    DateTime? createdAt,
  }) =>
      SwapOfferModel(
        offerId: offerId ?? this.offerId,
        listingId: listingId ?? this.listingId,
        offeredById: offeredById ?? this.offeredById,
        offeredItemId: offeredItemId ?? this.offeredItemId,
        offeredTitle: offeredTitle ?? this.offeredTitle,
        offeredImages: offeredImages ?? this.offeredImages,
        sellerId: sellerId ?? this.sellerId,
        message: message ?? this.message,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
}
