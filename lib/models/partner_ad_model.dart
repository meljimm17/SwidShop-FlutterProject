import 'package:cloud_firestore/cloud_firestore.dart';

/// A partner banner ad (Step 6). Created by admins; shown on the customer
/// Home feed while live. `link` is display text only (no URL launcher).
class PartnerAdModel {
  const PartnerAdModel({
    required this.adId,
    this.title = '',
    this.imageUrl = '',
    this.link = '',
    this.startsAt,
    this.endsAt,
    this.pricePaid = 0,
    this.active = true,
    this.createdAt,
  });

  final String adId;
  final String title;

  /// Cloudinary secure_url (uploaded by the admin like any listing photo).
  final String imageUrl;
  final String link;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final double pricePaid;

  /// Admin kill-switch; date window still applies when true.
  final bool active;
  final DateTime? createdAt;

  /// Live right now (client-side; expiry sweeps also flip [active]).
  bool get isLive {
    if (!active) return false;
    final now = DateTime.now();
    if (startsAt != null && startsAt!.isAfter(now)) return false;
    if (endsAt != null && !endsAt!.isAfter(now)) return false;
    return true;
  }

  factory PartnerAdModel.fromMap(String adId, Map<String, dynamic> map) {
    return PartnerAdModel(
      adId: adId,
      title: map['title'] as String? ?? '',
      imageUrl: map['imageUrl'] as String? ?? '',
      link: map['link'] as String? ?? '',
      startsAt: (map['startsAt'] as Timestamp?)?.toDate(),
      endsAt: (map['endsAt'] as Timestamp?)?.toDate(),
      pricePaid: (map['pricePaid'] as num?)?.toDouble() ?? 0,
      active: map['active'] as bool? ?? true,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'imageUrl': imageUrl,
        'link': link,
        'startsAt':
            startsAt != null ? Timestamp.fromDate(startsAt!) : null,
        'endsAt': endsAt != null ? Timestamp.fromDate(endsAt!) : null,
        'pricePaid': pricePaid,
        'active': active,
        'createdAt':
            createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      };

  PartnerAdModel copyWith({
    String? adId,
    String? title,
    String? imageUrl,
    String? link,
    DateTime? startsAt,
    DateTime? endsAt,
    double? pricePaid,
    bool? active,
    DateTime? createdAt,
  }) =>
      PartnerAdModel(
        adId: adId ?? this.adId,
        title: title ?? this.title,
        imageUrl: imageUrl ?? this.imageUrl,
        link: link ?? this.link,
        startsAt: startsAt ?? this.startsAt,
        endsAt: endsAt ?? this.endsAt,
        pricePaid: pricePaid ?? this.pricePaid,
        active: active ?? this.active,
        createdAt: createdAt ?? this.createdAt,
      );
}
