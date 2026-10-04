/// SwidShop application-wide constant values.
///
/// Central place for configuration that would otherwise be hard-coded
/// throughout the app (Cloudinary credentials, Firestore collection names,
/// storage folder builders, etc.).
library;

class AppConstants {
  AppConstants._();

  /// App / brand metadata.
  static const String appName = 'SwidShop';
  static const String appTagline = 'Buy, Bid & Swap';

  /// Firebase project id.
  static const String firebaseProjectId = 'swidshop-d8ccf';

  // ---------------------------------------------------------------------------
  // Demo admin login (class testing only — the "Continue as Admin" button).
  //
  // Anyone with the app can use these, by design: live Firestore rules are
  // `allow read, write: if true` for class testing, so there is nothing to
  // protect yet. Before any real release, DELETE this button + account and
  // provision admins from the console instead.
  // ---------------------------------------------------------------------------

  /// Demo admin email for one-tap class demos.
  static const String demoAdminEmail = 'admin@swidshop.demo';

  /// Demo admin password for one-tap class demos.
  static const String demoAdminPassword = 'swidshop-admin-2026';

  // ---------------------------------------------------------------------------
  // Cloudinary
  // See https://cloudinary.com/documentation/upload_presets
  // ---------------------------------------------------------------------------

  /// The Cloudinary "cloud name" for this project.
  static const String cloudinaryCloudName = 'u0sntfxy';

  /// The unsigned upload preset used by client-side uploads.
  static const String cloudinaryUploadPreset = 'swidshop_uploads';

  /// Base endpoint for unsigned image uploads.
  static const String cloudinaryUploadUrl =
      'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/upload';


  // ---------------------------------------------------------------------------
  // Cloudinary folder helpers
  // Only these two folder prefixes are permitted by the upload preset.
  // ---------------------------------------------------------------------------

  /// Folder for listing item photos: `listings/{listingId}`.
  static String listingsFolder(String listingId) => 'listings/$listingId';

  /// Folder for profile photos: `avatars/{uid}`.
  static String avatarsFolder(String uid) => 'avatars/$uid';

  // ---------------------------------------------------------------------------
  // Firestore collection / subcollection names
  // ---------------------------------------------------------------------------

  static const String usersCollection = 'users';

  /// Owner/admin-only subcollection: `users/{uid}/private/details`
  /// (phone, street address, ID photos, terms acceptance).
  static const String userPrivateSubcollection = 'private';
  static const String userPrivateDetailsDoc = 'details';

  /// Bump when the Terms & Conditions text changes materially.
  static const String termsVersion = '2026-10-04';
  static const String listingsCollection = 'listings';
  static const String bidsCollection = 'bids';
  static const String swapOffersCollection = 'swapOffers';
  static const String transactionsCollection = 'transactions';
  static const String ratingsCollection = 'ratings';
  static const String reportsCollection = 'reports';
  static const String categoriesCollection = 'categories';

  /// Subcollection: `chats/{transactionId}/messages`.
  static const String chatsCollection = 'chats';
  static const String messagesSubcollection = 'messages';

  /// Subcollection: `notifications/{uid}/items`.
  static const String notificationsCollection = 'notifications';
  static const String notificationsItemsSubcollection = 'items';
}
