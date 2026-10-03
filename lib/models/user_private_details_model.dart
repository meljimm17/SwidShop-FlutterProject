import 'package:cloud_firestore/cloud_firestore.dart';

/// Government ID types accepted at registration.
enum GovIdType {
  nationalId('national_id', 'Philippine National ID', hasBack: true),
  umid('umid_sss', 'UMID / SSS', hasBack: true),
  driversLicense('drivers_license', "Driver's License", hasBack: true),
  passport('passport', 'Passport', hasBack: false);

  const GovIdType(this.value, this.label, {required this.hasBack});

  final String value;
  final String label;

  /// Passports only need the photo page.
  final bool hasBack;

  static GovIdType? fromValue(String? value) {
    for (final t in GovIdType.values) {
      if (t.value == value) return t;
    }
    return null;
  }
}

/// Sensitive profile data kept at `users/{uid}/private/details`, readable
/// only by the owner and admins (the public `users/{uid}` doc is readable by
/// any signed-in user).
class UserPrivateDetails {
  const UserPrivateDetails({
    this.phone = '',
    this.street = '',
    this.idType,
    this.idFrontUrl = '',
    this.idBackUrl = '',
    this.idStatus = 'pending',
    this.termsVersion = '',
    this.termsAcceptedAt,
  });

  /// E.164, e.g. `+639171234567`.
  final String phone;
  final String street;
  final GovIdType? idType;
  final String idFrontUrl;
  final String idBackUrl;

  /// pending | verified | rejected — set by admins after review.
  final String idStatus;

  final String termsVersion;
  final DateTime? termsAcceptedAt;

  factory UserPrivateDetails.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UserPrivateDetails();
    return UserPrivateDetails(
      phone: map['phone'] as String? ?? '',
      street: map['street'] as String? ?? '',
      idType: GovIdType.fromValue(map['idType'] as String?),
      idFrontUrl: map['idFrontUrl'] as String? ?? '',
      idBackUrl: map['idBackUrl'] as String? ?? '',
      idStatus: map['idStatus'] as String? ?? 'pending',
      termsVersion: map['termsVersion'] as String? ?? '',
      termsAcceptedAt: (map['termsAcceptedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'phone': phone,
        'street': street,
        'idType': idType?.value,
        'idFrontUrl': idFrontUrl,
        'idBackUrl': idBackUrl,
        'idStatus': idStatus,
        'termsVersion': termsVersion,
        'termsAcceptedAt': termsAcceptedAt != null
            ? Timestamp.fromDate(termsAcceptedAt!)
            : null,
      };
}
