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
  }) =>
      AddressModel(
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
    this.profileComplete = true,
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

  /// One of: customer | seller | both | admin.
  final UserRole role;

  final AddressModel address;

  /// Date of birth collected at registration (optional in older docs).
  final DateTime? dob;

  final double avgRating;
  final int completedTransactions;
  final double completionRate;
  final bool trustedBadge;

  /// False until role, profile and terms steps are done. Google sign-ups
  /// start incomplete and are routed back into registration. Missing on
  /// older docs, which are treated as complete.
  final bool profileComplete;

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
      address: AddressModel.fromMap(map['address'] as Map<String, dynamic>?),
      dob: (map['dob'] as Timestamp?)?.toDate(),
      avgRating: (map['avgRating'] as num?)?.toDouble() ?? 0,
      completedTransactions:
          (map['completedTransactions'] as num?)?.toInt() ?? 0,
      completionRate: (map['completionRate'] as num?)?.toDouble() ?? 0,
      trustedBadge: map['trustedBadge'] as bool? ?? false,
      profileComplete: map['profileComplete'] as bool? ?? true,
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
    bool? profileComplete,
    DateTime? createdAt,
  }) =>
      UserModel(
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
        completedTransactions:
            completedTransactions ?? this.completedTransactions,
        completionRate: completionRate ?? this.completionRate,
        trustedBadge: trustedBadge ?? this.trustedBadge,
        profileComplete: profileComplete ?? this.profileComplete,
        createdAt: createdAt ?? this.createdAt,
      );
}

/// The role a user plays within SwidShop.
enum UserRole {
  customer('customer'),
  seller('seller'),
  both('both'),
  admin('admin');

  const UserRole(this.value);

  final String value;

  static UserRole fromValue(String? value) {
    return UserRole.values.firstWhere(
      (e) => e.value == value,
      orElse: () => UserRole.customer,
    );
  }

  /// Seller or admin can post listings.
  bool get canSell => this == UserRole.seller || this == UserRole.both || this == UserRole.admin;
}
