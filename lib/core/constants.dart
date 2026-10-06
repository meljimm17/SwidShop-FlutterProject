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
  // Admin login (Login → "Admin login": username + password dialog).
  //
  // The username maps to one Firebase Auth account. Class-project setup:
  // before any real release, provision admins from the console and change
  // these credentials.
  // ---------------------------------------------------------------------------

  /// Username typed in the admin login dialog.
  static const String adminUsername = 'admin';

  /// Password typed in the admin login dialog (also the Firebase password).
  static const String adminPassword = 'admin123';

  /// Firebase Auth email behind the admin username (existing account).
  static const String adminEmail = 'admin@swidshop.demo';

  /// Earlier password of [adminEmail]; migrated to [adminPassword] on the
  /// first successful admin login.
  static const String legacyAdminPassword = 'swidshop-admin-2026';

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

  /// Folder for photos sent in a deal chat. Kept under the `listings/`
  /// prefix because the unsigned preset only accepts listings/ or avatars/.
  static String chatFolder(String transactionId) =>
      listingsFolder('chat-$transactionId');

  /// Folder for photos of an item offered in a swap without a listing.
  /// Under the `listings/` prefix (the only one the preset accepts besides
  /// avatars/).
  static String swapOfferFolder(String offerId) =>
      listingsFolder('swap-$offerId');

  /// Max photos on a photo swap offer.
  static const int maxSwapOfferPhotos = 4;

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
  static const String termsVersion = '2026-10-07';

  /// Trusted Seller eligibility thresholds (mirrored in functions/index.js).
  static const int trustedMinCompletedTransactions = 10;
  static const double trustedMinCompletionRate = 0.9;
  static const double trustedMinAvgRating = 4.5;

  static const String listingsCollection = 'listings';
  static const String bidsCollection = 'bids';
  static const String swapOffersCollection = 'swapOffers';
  static const String transactionsCollection = 'transactions';
  static const String ratingsCollection = 'ratings';
  static const String reportsCollection = 'reports';
  static const String categoriesCollection = 'categories';

  /// Role-change requests: `roleRequests/{uid}` (one per user).
  static const String roleRequestsCollection = 'roleRequests';

  /// Payment records from the simulated GCash flow (Step 1 — NO real
  /// money). Created by the payer; immutable afterwards (see rules).
  static const String paymentsCollection = 'payments';

  /// Where the earlier build saved payment records (same fields). Read-only
  /// now: admin revenue merges it so older payments still count.
  static const String legacyPaymentsCollection = 'demoPurchases';

  /// Partner banner ads (Step 6).
  static const String partnerAdsCollection = 'partnerAds';

  // ---------------------------------------------------------------------------
  // Monetization constants (demo only — no real money, no payment provider).
  // Posting is always free; swaps have no commission.
  // ---------------------------------------------------------------------------

  /// Plan key → commission rate on Bidding + Buy Now final price.
  static const Map<String, double> feeRates = {
    'free': 0.05,
    'plus': 0.04,
    'pro': 0.03,
  };

  /// Days after the deal before an unpaid fee is due.
  static const int feeDueDays = 7;

  /// Days after deal creation on which reminder notifications are sent.
  static const List<int> feeReminderDays = [1, 3, 6];

  /// Seller plan keys (users.plan).
  static const List<String> plans = ['free', 'plus', 'pro'];

  /// Max photos per listing by plan ('pack' = one-time Photo Pack).
  static const Map<String, int> photoLimits = {
    'free': 3,
    'pack': 8,
    'plus': 8,
    'pro': 15,
  };

  /// Longest auction per plan (Pro add-on unlocks 10–14 days).
  static const int maxAuctionDays = 7;
  static const int maxProAuctionDays = 14;

  /// Shortest auction a seller can post (e.g. a 10-minute flash auction).
  static const Duration minAuctionDuration = Duration(minutes: 5);

  /// When the seller changes a LIVE auction's end time, it must still be at
  /// least this far away (bidders need a moment to react).
  static const Duration minAuctionTimeLeft = Duration(minutes: 1);

  /// Quick picks on the Post Listing screen (Custom covers anything else).
  static const List<Duration> auctionPresets = [
    Duration(minutes: 10),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 6),
    Duration(days: 1),
    Duration(days: 3),
    Duration(days: 7),
  ];

  /// Extra quick picks for Pro sellers.
  static const List<Duration> proAuctionPresets = [
    Duration(days: 10),
    Duration(days: 14),
  ];

  /// Longest auction (from now) for a seller on [effectivePlan].
  static Duration maxAuctionDuration(String effectivePlan) => Duration(
        days: effectivePlan == 'pro' ? maxProAuctionDays : maxAuctionDays,
      );

  /// Minimum time between two Bumps of the same listing (Pro).
  static const Duration bumpCooldown = Duration(hours: 24);

  /// Available boost durations in days (Step 4).
  static const List<int> boostDurations = [3, 7, 14];

  /// Demo prices (GCash demo flow — no real money).
  static const Map<String, double> planPrices = {
    'plus': 149,
    'pro': 299,
  };

  /// Paid plan length in days.
  static const int planDays = 30;

  /// Boost prices by duration in days (demo).
  static const Map<int, double> boostPrices = {3: 49, 7: 99, 14: 179};

  /// Single-listing featured price (demo) and its window.
  static const double featuredPrice = 79;
  static const int featuredDays = 7;

  /// One-time Photo Pack price for free sellers (demo).
  static const double photoPackPrice = 49;

  /// How long a Highlighted listing stays highlighted (Step 3, Pro).
  static const int highlightDays = 7;

  /// Carousel auto-slide interval (Step 4).
  static const Duration sponsoredSlideInterval = Duration(seconds: 4);

  /// Subcollection: `chats/{transactionId}/messages`.
  static const String chatsCollection = 'chats';
  static const String messagesSubcollection = 'messages';

  /// Subcollection: `notifications/{uid}/items`.
  static const String notificationsCollection = 'notifications';
  static const String notificationsItemsSubcollection = 'items';
}

/// Pure platform-fee math shared by every deal flow (and unit tests).
/// The `closeAuctions` Cloud Function mirrors these numbers in JS.
class Fees {
  Fees._();

  /// Commission rate for a seller on [effectivePlan] (unknown → free).
  static double rateFor(String effectivePlan) =>
      AppConstants.feeRates[effectivePlan] ?? AppConstants.feeRates['free']!;

  /// Fee in pesos, rounded to centavos (avoids 61.70000000000001).
  static double amountFor(double price, double rate) =>
      (price * rate * 100).round() / 100;

  /// When a fee stamped at [dealTime] falls due.
  static DateTime dueFrom(DateTime dealTime) =>
      dealTime.add(const Duration(days: AppConstants.feeDueDays));

  /// True on the days after the deal when a reminder goes out.
  static bool isReminderDay(DateTime dealTime, DateTime now) =>
      AppConstants.feeReminderDays.contains(now.difference(dealTime).inDays);
}
