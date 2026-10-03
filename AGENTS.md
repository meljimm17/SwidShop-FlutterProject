# AGENTS.md — SwidShop

Flutter marketplace app (buy, bid & swap) + Firebase backend. Single package `swidshop`, Dart SDK `^3.13.1`. Entry: `lib/main.dart` (`_AuthGate` → `LoginScreen` or `HomeScreen`).

## Commands

- `flutter pub get` — install deps
- `flutter analyze` — lint (uses `package:flutter_lints/flutter.yaml`; platform dirs excluded in `analysis_options.yaml`)
- `flutter test` — all tests; `flutter test test/widget_test.dart` — single file (only test file)
- `flutter run` — dev app (needs Firebase config; `lib/firebase_options.dart` is committed)
- `dart run flutter_launcher_icons` — regenerate icons (config at bottom of `pubspec.yaml`)
- Functions (in `functions/`, Node 20): `npm run serve` / `npm run deploy` / `npm run logs` (wrappers around `firebase ... --only functions`)
- Firestore: `firebase deploy --only firestore:rules,firestore:indexes`

## Architecture

- `lib/core/` — `constants.dart` (brand, Cloudinary, collection names), `theme.dart`, `utils.dart`
- `lib/models/` — `fromMap(docId, map)` / `toMap()` with enums carrying `.value`; IDs live both as doc ID and `*Id` field
- `lib/services/firestore_service.dart` — only Firestore access layer; `auth_service.dart` (email + Google Sign-In 7.x), `storage_service.dart` (Cloudinary), `notification_service.dart`
- `lib/providers/` — `AuthProvider`, `ListingProvider` (client-side type/category/search filter over `streamActiveListings`), `SellerProvider` (proxy of AuthProvider; seller's listings + swap offers + transactions, started lazily by seller screens via `start()`; pure counts in `SellerStats`); wired in `main.dart` via `MultiProvider`
- `lib/screens/seller/` (Phase 2) — `SellerShell` (bottom nav: Dashboard · Listings · Orders · Messages · Profile; `SellerShell.goTo(context, SellerTab.x)` switches tabs) is the root for `seller` (via `homeForRole`) and is pushed from Home's store icon for `both`. Tabs: `dashboard_screen` (store card, Store Pulse, tools, Live Seller Feed), `my_listings_screen` (hub + All/Active/Sold/Done/Expired), `seller_orders_screen`, `seller_messages_screen`, `ProfileScreen(embedded: true)`. Pushed: `post_listing_screen` (create + edit via `existing:`; reserve price, specs, delivery options), `monitor_bidding_screen` (+ `AuctionsScreen`), `swap_offers_screen` (accept/decline via `swap_offer_actions.dart`), `sales_history_screen`, `analytics_screen`. `lib/screens/shared/transaction_chat_screen.dart` is the basic Chat & Status screen (Phase 3.8 extends it).
- Seller UI follows the user's reference mockups but with NO escrow, waybill/courier printing, or invented stats — every number (e.g. "+N this week", "% vs last month", sell-through) is computed in `SellerStats` from live data. `test/seller_shell_test.dart` renders the shell at 360×780 with fakes to catch overflows.
- `lib/screens/{auth,customer,seller,admin}/` — role-separated screens; `lib/widgets/` shared UI
- `functions/index.js` — `computeTrustBadge` (callable), `onTransactionWritten` (recompute trust), `closeAuctions` (every 15 min, closes expired `bid` listings, writes winning `transactions` doc)

## Build notes (Windows)

- Run one Gradle build at a time; overlapping builds leave daemons holding
  `*.lock` files (`Timeout waiting to lock ...`). Recover with
  `.\gradlew.bat --stop` in `android/` (kill the owner PID if it lingers).
- Prefer `.\gradlew.bat assembleDebug --no-daemon` on this machine — no
  orphaned daemons, no lock fights.
- If `:app:mergeDebugAssets` fails with `Unable to delete directory ...
  mergeDebugAssets` (a process holds `kernel_blob.bin` open), or
  `:app:compressDebugAssets` fails on alternating large files
  (`kernel_blob.bin`, `*.frag`, `*_snapshot_data`), the locker is Windows
  Defender real-time protection (`MsMpEng` — the only AV on this machine;
  confirmed via SecurityCenter2). This is environmental, not a code issue:
  `flutter analyze` + `flutter test` stay green.
- Defender exclusions must be added by the user in an elevated shell
  (we are not admin). Exact commands are in chat history / below.
- 8 GB RAM (~2 GB free during builds) also kills builds silently
  (exit 255 mid-`compileFlutterBuildDebug`); close heavy apps before building.
  `android/gradle.properties` keeps the Gradle heap at `-Xmx2560m` for this reason.
- VS Code Java extensions (Oracle Java, Red Hat Java, Gradle for Java) spawn
  their own Gradle daemons on `android/` and pub-cache plugins, producing bogus
  `jni` / `firebase_messaging` settings errors and lock fights. Keep them
  disabled for this workspace (`.vscode/settings.json` turns off their import).

## Auth flow (Phase 1)

- Launch: `SplashScreen` (logo on `AppColors.paper`, fixed ~1.5s, waits for auth+profile, 8s cap) → `destinationAfterAuth` or `LoginScreen`. There is no Welcome screen; Login is the signed-out root. No root auth gate; screens navigate explicitly.
- `lib/screens/auth/role_home.dart` — `homeForRole(role)` (seller→`SellerDashboardScreen`, admin→`AdminDashboardScreen`, else `HomeScreen`), `destinationAfterAuth(auth)` (unfinished profile → `RegisterScreen.completeProfile()`, else role home), `goAfterAuth(context)` and `signOutToLogin(context)`. Reuse these; never hardcode role routing.
- Login success → `goAfterAuth`; sign-out anywhere → `signOutToLogin`. Register is pushed over Login; success uses `pushAndRemoveUntil`.
- Guest mode: Login → "Browse as guest" → `AuthProvider.enterGuest()` (in-memory `isGuest`, auto-cleared on sign-in/out). Guests land on `HomeScreen` with a banner; avatar/bell push Login. Detail-screen actions are still stubs — gate them when implemented.
- Register is 4 steps (account → role → profile/address/ID → terms). Email flow on submit: `signUp(profileComplete: false)` → Cloudinary uploads (avatar + ID photos, all in `avatarsFolder(uid)`) → `savePrivateDetails` → `saveProfile(... profileComplete: true)`. Uploaded URLs are cached so retries don't re-upload; an interrupted sign-up resumes via `needsOnboarding`.
- `UserModel.profileComplete` defaults to `true` when the field is missing (legacy docs). First Google sign-in creates the doc with `false` and is routed into `RegisterScreen.completeProfile()` (step 1 = name + DOB only).
- Sensitive data (phone `+63…`, street, ID type/photos, terms version/acceptance) lives in `users/{uid}/private/details` (`UserPrivateDetails`), owner/admin-only in rules. The public `users/{uid}` doc is readable by every signed-in user — never put sensitive fields there.
- Terms text: `lib/screens/auth/terms_content.dart`; bump `AppConstants.termsVersion` on material changes. Keep it consistent with app behaviour (no payment handling/escrow; trust thresholds from `functions/index.js`).
- Google Sign-In (Android) relies on `default_web_client_id` from `google-services.json`, which only exists after the app's SHA-1 is registered in Firebase and the JSON is re-downloaded (`oauth_client` must not be empty).
- `firebase_auth` exports its own `AuthProvider` — import it with `hide AuthProvider` wherever ours is used.

## Conventions / gotchas

- Collection/subcollection names: always use `AppConstants` (`lib/core/constants.dart`); never hardcode strings.
- Images go to Cloudinary only (unsigned preset `swidshop_uploads`, cloud `u0sntfxy`); persist only the returned `secure_url` in Firestore. Folder must be `AppConstants.listingsFolder(id)` or `avatarsFolder(uid)` — preset rejects others. Unsigned uploads reject `eager`/`transformation` params — resize on-device (image_picker `maxWidth`) instead.
- `firestore.rules` is deny-by-default and enforces ownership fields (`sellerId`/`bidderId`/`offeredById`/`raterId`/`reportedBy`/`senderId` == `request.auth.uid`); client writes must set these correctly or they fail. `listings` read is public; most else requires auth; `categories` write and `reports` read are admin-only (`users/{uid}.role == 'admin'`).
- Chat lives at `chats/{transactionId}/messages` in code, rules, and schema — keep all three aligned; do not add alternate chat paths.
- Indexes/rules/functions are NOT deployed yet (live rules are open for class testing). So `FirestoreService` queries use equality filters only and sort client-side — no composite index needed. Keep it that way for new queries (no `orderBy` on a field other than the filter, no range+equality mixes) until indexes are deployed. `firestore.indexes.json` is kept for later.
- Auctions: `FirestoreService.closeAuctionIfEnded` (called by Monitor Bidding when the timer hits zero) and the `closeAuctions` function both use transaction id `auction_{listingId}` + an in-transaction `status == active` check → idempotent, no duplicates. Swap accept uses `swap_{offerId}`.
- `swapOffers.sellerId` is denormalised (listing owner) so sellers query offers by equality; `createSwapOffer` fills it if empty and rules enforce it. "Locked" listings (any bid → `currentHighestBid != null`, or any swap offer) can't be edited/delisted.
- Listing photos: `StorageService.compressForUpload` (JPEG 80%, longest edge 1600) then `uploadListingImage(..., onProgress:)` into `listings/{newListingId()}`.
- Bids must go through `FirestoreService.placeBid` (transaction checks `amount > currentHighestBid || startingBid` and bumps `currentHighestBid`); never write `bids` docs directly.
- UI: use `AppTheme.light` / `AppColors` (cream scaffold, coral primary, teal secondary) and shared widgets (`PrimaryButton`, `TopAppBar`, `TypeBadge`, etc.). Font is Plus Jakarta Sans via `AppTheme.fontFamily` — do not switch to `GoogleFonts.plusJakartaSansTextTheme()` (wrong `TextTheme` type; see comment in `theme.dart`).
- Tests in `test/widget_test.dart` deliberately avoid `Firebase.initializeApp` so they run as plain unit/widget tests. Keep new tests Firebase-free (inject `FirestoreService`/`FirebaseAuth` fakes via constructor params).
