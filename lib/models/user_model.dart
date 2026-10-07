import 'package:cloud_firestore/cloud_firestore.dart';

/// Nested address value object for a [UserModel].
class AddressModel {
  const AddressModel({
    this.city = '',
    this.province = '',
    this.zipCode = '',
    this.country = 'Philippines',
  });

  final String city;
  final String province;
  final String zipCode;
  final String country;

  factory AddressModel.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AddressModel();
    return AddressModel(
      city: map['city'] as String? ?? '',
      province: map['province'] as String? ?? '',
      zipCode: map['zipCode'] as String? ?? '',
      country: map['country'] as String? ?? 'Philippines',
    );
  }

  Map<String, dynamic> toMap() => {
    'city': city,
    'province': province,
    'zipCode': zipCode,
    'country': country,
  };

  AddressModel copyWith({
    String? city,
    String? province,
    String? zipCode,
    String? country,
  }) => AddressModel(
    city: city ?? this.city,
    province: province ?? this.province,
    zipCode: zipCode ?? this.zipCode,
    country: country ?? this.country,
  );
}

/// A SwidShop user. The Firestore document id is the Firebase Auth uid.
class UserModel {
  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.photoUrl = '',
    this.role = UserRole.customer,
    this.address = const AddressModel(),
    this.dob,
    this.avgRating = 0,
    this.completedTransactions = 0,
    this.completionRate = 0,
    this.trustedBadge = false,
    this.trustedBadgeEligible = false,
    this.trustedOpenReports = 0,
    this.profileComplete = true,
    this.accountStatus = AccountStatus.active,
    this.plan = 'free',
    this.planUntil,
    this.boostedUntil,
    this.holdManual = false,
    this.legacySellerRole = false,
    this.favorites = const [],
    this.following = const [],
    this.createdAt,
  });

  final String uid;
  final String name;
  final String email;

  /// Name parts from registration. [name] stays the display name
  /// (`First Last`); these may be empty on older / Google-created docs.
  final String firstName;
  final String middleName;
  final String lastName;

  final String photoUrl;

  /// Customer roles plus staff-only admin and superadmin roles.
  final UserRole role;

  final AddressModel address;

  /// Date of birth collected at registration (optional in older docs).
  final DateTime? dob;

  final double avgRating;
  final int completedTransactions;
  final double completionRate;
  final bool trustedBadge;

  /// Server-calculated Trusted Seller status; admin approval is still needed.
  final bool trustedBadgeEligible;

  /// Pending reports against this seller, their listings, or their ratings.
  final int trustedOpenReports;

  /// False until role, profile and terms steps are done. Google sign-ups
  /// start incomplete and are routed back into registration. Missing on
  /// older docs, which are treated as complete.
  final bool profileComplete;

  /// Listing ids the user hearted (Phase 3.4).
  final List<String> favorites;

  /// Seller uids the user follows (Phase 3.3).
  final List<String> following;

  /// Moderation state (Phase 4.2). Missing on older docs → active.
  final AccountStatus accountStatus;

  /// Seller plan as stored: 'free' | 'plus' | 'pro'. Use [effectivePlan]
  /// for every perk/fee decision — a lapsed plan may not be reset yet.
  final String plan;

  /// When the paid plan lapses (null with a paid plan = no end date,
  /// e.g. set by an admin).
  final DateTime? planUntil;

  /// Shop boost expiry (null = not boosted).
  final DateTime? boostedUntil;

  /// True when an admin placed the fee hold by hand: paying fees does not
  /// lift it, only an admin does. Server-managed — never written by
  /// [toMap].
  final bool holdManual;

  /// True when the stored role is the retired seller-only value; the app
  /// treats it as [UserRole.both] and rewrites it (never in [toMap]).
  final bool legacySellerRole;

  /// The plan that applies right now: the stored plan while its window is
  /// open, otherwise 'free'. Unknown values fall back to 'free'.
  String get effectivePlan => effectivePlanOf(plan, planUntil);

  /// Shared by models and tests: [plan] while [until] is open (or null).
  static String effectivePlanOf(String plan, DateTime? until, {DateTime? now}) {
    if (plan != 'plus' && plan != 'pro') return 'free';
    if (until != null && !until.isAfter(now ?? DateTime.now())) return 'free';
    return plan;
  }

  bool get isPro => effectivePlan == 'pro';

  /// Plus and Pro sellers carry the Verified badge.
  bool get isVerifiedSeller => effectivePlan != 'free';

  /// True while the paid shop boost is running.
  bool get isBoosted =>
      boostedUntil != null && boostedUntil!.isAfter(DateTime.now());

  final DateTime? createdAt;

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserModel(
      uid: uid,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      firstName: map['firstName'] as String? ?? '',
      middleName: map['middleName'] as String? ?? '',
      lastName: map['lastName'] as String? ?? '',
      photoUrl: map['photoUrl'] as String? ?? '',
      role: UserRole.fromValue(map['role'] as String?),
      legacySellerRole: map['role'] == UserRole.legacySellerValue,
      address: AddressModel.fromMap(map['address'] as Map<String, dynamic>?),
      dob: (map['dob'] as Timestamp?)?.toDate(),
      avgRating: (map['avgRating'] as num?)?.toDouble() ?? 0,
      completedTransactions:
          (map['completedTransactions'] as num?)?.toInt() ?? 0,
      completionRate: (map['completionRate'] as num?)?.toDouble() ?? 0,
      trustedBadge: map['trustedBadge'] as bool? ?? false,
      trustedBadgeEligible: map['trustedBadgeEligible'] as bool? ?? false,
      trustedOpenReports: (map['trustedOpenReports'] as num?)?.toInt() ?? 0,
      profileComplete: map['profileComplete'] as bool? ?? true,
      accountStatus: AccountStatus.fromValue(map['accountStatus'] as String?),
      plan: map['plan'] as String? ?? 'free',
      planUntil: (map['planUntil'] as Timestamp?)?.toDate(),
      boostedUntil: (map['boostedUntil'] as Timestamp?)?.toDate(),
      holdManual: map['holdManual'] as bool? ?? false,
      favorites:
          (map['favorites'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      following:
          (map['following'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    'email': email,
    'firstName': firstName,
    'middleName': middleName,
    'lastName': lastName,
    'photoUrl': photoUrl,
    'role': role.value,
    'address': address.toMap(),
    'dob': dob != null ? Timestamp.fromDate(dob!) : null,
    'avgRating': avgRating,
    'completedTransactions': completedTransactions,
    'completionRate': completionRate,
    'trustedBadge': trustedBadge,
    'profileComplete': profileComplete,
    'accountStatus': accountStatus.value,
    'plan': plan,
    'planUntil': planUntil != null ? Timestamp.fromDate(planUntil!) : null,
    'boostedUntil': boostedUntil != null
        ? Timestamp.fromDate(boostedUntil!)
        : null,
    'favorites': favorites,
    'following': following,
    'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
  };

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? firstName,
    String? middleName,
    String? lastName,
    String? photoUrl,
    UserRole? role,
    AddressModel? address,
    DateTime? dob,
    double? avgRating,
    int? completedTransactions,
    double? completionRate,
    bool? trustedBadge,
    bool? trustedBadgeEligible,
    int? trustedOpenReports,
    bool? profileComplete,
    AccountStatus? accountStatus,
    String? plan,
    DateTime? planUntil,
    DateTime? boostedUntil,
    bool? holdManual,
    List<String>? favorites,
    List<String>? following,
    DateTime? createdAt,
  }) => UserModel(
    uid: uid ?? this.uid,
    name: name ?? this.name,
    email: email ?? this.email,
    firstName: firstName ?? this.firstName,
    middleName: middleName ?? this.middleName,
    lastName: lastName ?? this.lastName,
    photoUrl: photoUrl ?? this.photoUrl,
    role: role ?? this.role,
    address: address ?? this.address,
    dob: dob ?? this.dob,
    avgRating: avgRating ?? this.avgRating,
    completedTransactions: completedTransactions ?? this.completedTransactions,
    completionRate: completionRate ?? this.completionRate,
    trustedBadge: trustedBadge ?? this.trustedBadge,
    trustedBadgeEligible: trustedBadgeEligible ?? this.trustedBadgeEligible,
    trustedOpenReports: trustedOpenReports ?? this.trustedOpenReports,
    profileComplete: profileComplete ?? this.profileComplete,
    accountStatus: accountStatus ?? this.accountStatus,
    plan: plan ?? this.plan,
    planUntil: planUntil ?? this.planUntil,
    boostedUntil: boostedUntil ?? this.boostedUntil,
    holdManual: holdManual ?? this.holdManual,
    favorites: favorites ?? this.favorites,
    following: following ?? this.following,
    createdAt: createdAt ?? this.createdAt,
  );
}

/// Moderation state of an account. Missing on older docs → active.
///
/// `onHold` is fee-hold ONLY (unpaid platform fees): unlike suspended/banned
/// it never blocks sign-in — it only blocks posting listings and accepting
/// swaps until fees are paid.
enum AccountStatus {
  active('active'),
  suspended('suspended'),
  banned('banned'),
  onHold('on_hold');

  const AccountStatus(this.value);

  final String value;

  static AccountStatus fromValue(String? value) => AccountStatus.values
      .firstWhere((e) => e.value == value, orElse: () => AccountStatus.active);
}

/// The role a user plays within SwidShop: Customer, or Customer + Seller
/// ("both"). There is no seller-only role any more — a stored legacy
/// `'seller'` reads as [both] (see [legacySellerValue]).
enum UserRole {
  customer('customer'),
  both('both'),
  admin('admin'),
  superadmin('superadmin');

  const UserRole(this.value);

  final String value;

  /// The retired seller-only role value still found on older docs.
  static const String legacySellerValue = 'seller';

  static UserRole fromValue(String? value) {
    if (value == legacySellerValue) return UserRole.both;
    return UserRole.values.firstWhere(
      (e) => e.value == value,
      orElse: () => UserRole.customer,
    );
  }

  bool get isStaff => this == UserRole.admin || this == UserRole.superadmin;

  /// Only customer accounts can begin marketplace activity.
  bool get canUseMarketplace => !isStaff;

  /// Only Customer + Seller accounts can post listings.
  bool get canSell => this == UserRole.both;

  /// Human label for screens ("Customer + Seller" for both).
  String get label => switch (this) {
    UserRole.customer => 'Customer',
    UserRole.both => 'Customer + Seller',
    UserRole.admin => 'Admin',
    UserRole.superadmin => 'Superadmin',
  };
}
