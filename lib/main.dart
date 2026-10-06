import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/listing_provider.dart';
import 'providers/seller_provider.dart';
import 'screens/auth/splash_screen.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register the background message handler before the app renders.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const SwidShopApp());
}

class SwidShopApp extends StatefulWidget {
  const SwidShopApp({super.key});

  @override
  State<SwidShopApp> createState() => _SwidShopAppState();
}

class _SwidShopAppState extends State<SwidShopApp>
    with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  Timer? _auctionTimer;
  bool _closingAuctions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _closeEndedAuctions();
    _auctionTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _closeEndedAuctions(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _closeEndedAuctions();
  }

  Future<void> _closeEndedAuctions() async {
    if (_closingAuctions) return;
    _closingAuctions = true;
    try {
      await _firestore.closeEndedAuctions();
    } catch (e) {
      debugPrint('closeEndedAuctions: $e');
    } finally {
      _closingAuctions = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auctionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ListingProvider()),
        ChangeNotifierProxyProvider<AuthProvider, SellerProvider>(
          create: (_) => SellerProvider(),
          update: (_, auth, seller) =>
              (seller ?? SellerProvider())..setUser(auth.firebaseUser?.uid),
        ),
        Provider(create: (_) => NotificationService()),
      ],
      child: MaterialApp(
        title: 'SwidShop',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const SplashScreen(),
      ),
    );
  }
}
