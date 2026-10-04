import 'package:cloud_firestore/cloud_firestore.dart';

/// How a listing can be acquired.
enum ListingType {
  buyNow('buyNow'),
  bid('bid'),
  swap('swap');

  const ListingType(this.value);

  final String value;

  static ListingType fromValue(String? value) => ListingType.values.firstWhere(
        (e) => e.value == value,
        orElse: () => ListingType.buyNow,
      );
}

/// How the item can be handed over (stored as [value] strings).
enum DeliveryOption {
  lalamove('lalamove', 'Lalamove / Grab'),
  jnt('jnt', 'J&T Express'),
  lbc('lbc', 'LBC'),
  meetup('meetup', 'Meet-up');

  const DeliveryOption(this.value, this.label);

  final String value;
  final String label;

  static DeliveryOption? fromValue(String value) {
    for (final o in DeliveryOption.values) {
      if (o.value == value) return o;
    }
    return null;
  }
}

/// Lifecycle status of a listing.
enum ListingStatus {
  active('active'),
  sold('sold'),
  expired('expired'),
  removed('removed');

  const ListingStatus(this.value);

  final String value;

  static ListingStatus fromValue(String? value) =>
      ListingStatus.values.firstWhere(
        (e) => e.value == value,
        orElse: () => ListingStatus.active,
      );
}

/// A marketplace listing. Firestore document id is an auto id.
class ListingModel {
  /// Condition choices offered by Post Listing — shared by search filters.
  static const List<String> conditions = [
    'Brand new',
    'Like new',
    'Gently used',
    'Used',
  ];

  const ListingModel({
    required this.listingId,
    required this.sellerId,
    required this.title,
    this.description = '',
    this.category = '',
    this.condition = '',
    this.size = '',
    this.fabric = '',
    this.brand = '',
    this.deliveryOptions = const <String>[],
    this.meetupSpot = '',
    this.images = const <String>[],
    this.type = ListingType.buyNow,
    this.price,
    this.startingBid,
    this.currentHighestBid,
    this.minIncrement,
    this.auctionEndAt,
    this.reservePrice,
    this.bidCount = 0,
    this.highestBidderId = '',
    this.swapOpen = false,
    this.swapWants = '',
    this.swapOnly = true,
    this.status = ListingStatus.active,
    this.createdAt,
  });

  final String listingId;
  final String sellerId;
  final String title;
  final String description;
  final String category;
  final String condition;

  /// Garment specs (free text, optional).
  final String size;
  final String fabric;
  final String brand;

  /// Handover methods the seller accepts — see [DeliveryOption].
  final List<String> deliveryOptions;

  /// Preferred meet-up place when [DeliveryOption.meetup] is offered.
  final String meetupSpot;

  /// Cloudinary secure_url strings (never raw files).
  final List<String> images;

  final ListingType type;

  /// Buy Now only.
  final double? price;

  /// Bid only.
  final double? startingBid;
  final double? currentHighestBid;
  final double? minIncrement;
  final DateTime? auctionEndAt;

  /// Bid only: hidden minimum. Below it the auction ends unsold (expired).
  final double? reservePrice;

  /// Bid only: maintained by `FirestoreService.placeBid`.
  final int bidCount;
  final String highestBidderId;

  /// Swap enabled?
  final bool swapOpen;

  /// Swap only: what the seller wants in return, e.g. "Size M denim jacket".
  final String swapWants;

  /// Swap only: true = trade only; false = a cash [price] is also accepted.
  final bool swapOnly;

  /// Price shown on cards / feed: current bid, fixed price, or swap cash price.
  double? get displayPrice =>
      type == ListingType.bid ? (currentHighestBid ?? startingBid) : price;

  /// Has received at least one bid (placeBid always sets currentHighestBid).
  bool get hasBids => currentHighestBid != null;

  final ListingStatus status;
  final DateTime? createdAt;

  factory ListingModel.fromMap(String listingId, Map<String, dynamic> map) {
    return ListingModel(
      listingId: listingId,
      sellerId: map['sellerId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? '',
      condition: map['condition'] as String? ?? '',
      size: map['size'] as String? ?? '',
      fabric: map['fabric'] as String? ?? '',
      brand: map['brand'] as String? ?? '',
      deliveryOptions: (map['deliveryOptions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      meetupSpot: map['meetupSpot'] as String? ?? '',
      images: (map['images'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      type: ListingType.fromValue(map['type'] as String?),
      price: (map['price'] as num?)?.toDouble(),
      startingBid: (map['startingBid'] as num?)?.toDouble(),
      currentHighestBid: (map['currentHighestBid'] as num?)?.toDouble(),
      minIncrement: (map['minIncrement'] as num?)?.toDouble(),
      auctionEndAt: (map['auctionEndAt'] as Timestamp?)?.toDate(),
      reservePrice: (map['reservePrice'] as num?)?.toDouble(),
      bidCount: (map['bidCount'] as num?)?.toInt() ?? 0,
      highestBidderId: map['highestBidderId'] as String? ?? '',
      swapOpen: map['swapOpen'] as bool? ?? false,
      swapWants: map['swapWants'] as String? ?? '',
      swapOnly: map['swapOnly'] as bool? ?? true,
      status: ListingStatus.fromValue(map['status'] as String?),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'listingId': listingId,
        'sellerId': sellerId,
        'title': title,
        'description': description,
        'category': category,
        'condition': condition,
        'size': size,
        'fabric': fabric,
        'brand': brand,
        'deliveryOptions': deliveryOptions,
        'meetupSpot': meetupSpot,
        'images': images,
        'type': type.value,
        'price': price,
        'startingBid': startingBid,
        'currentHighestBid': currentHighestBid,
        'minIncrement': minIncrement,
        'auctionEndAt':
            auctionEndAt != null ? Timestamp.fromDate(auctionEndAt!) : null,
        'reservePrice': reservePrice,
        'bidCount': bidCount,
        'highestBidderId': highestBidderId,
        'swapOpen': swapOpen,
        'swapWants': swapWants,
        'swapOnly': swapOnly,
        'status': status.value,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      };

  ListingModel copyWith({
    String? listingId,
    String? sellerId,
    String? title,
    String? description,
    String? category,
    String? condition,
    String? size,
    String? fabric,
    String? brand,
    List<String>? deliveryOptions,
    String? meetupSpot,
    List<String>? images,
    ListingType? type,
    double? price,
    double? startingBid,
    double? currentHighestBid,
    double? minIncrement,
    DateTime? auctionEndAt,
    double? reservePrice,
    int? bidCount,
    String? highestBidderId,
    bool? swapOpen,
    String? swapWants,
    bool? swapOnly,
    ListingStatus? status,
    DateTime? createdAt,
  }) =>
      ListingModel(
        listingId: listingId ?? this.listingId,
        sellerId: sellerId ?? this.sellerId,
        title: title ?? this.title,
        description: description ?? this.description,
        category: category ?? this.category,
        condition: condition ?? this.condition,
        size: size ?? this.size,
        fabric: fabric ?? this.fabric,
        brand: brand ?? this.brand,
        deliveryOptions: deliveryOptions ?? this.deliveryOptions,
        meetupSpot: meetupSpot ?? this.meetupSpot,
        images: images ?? this.images,
        type: type ?? this.type,
        price: price ?? this.price,
        startingBid: startingBid ?? this.startingBid,
        currentHighestBid: currentHighestBid ?? this.currentHighestBid,
        minIncrement: minIncrement ?? this.minIncrement,
        auctionEndAt: auctionEndAt ?? this.auctionEndAt,
        reservePrice: reservePrice ?? this.reservePrice,
        bidCount: bidCount ?? this.bidCount,
        highestBidderId: highestBidderId ?? this.highestBidderId,
        swapOpen: swapOpen ?? this.swapOpen,
        swapWants: swapWants ?? this.swapWants,
        swapOnly: swapOnly ?? this.swapOnly,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
}
