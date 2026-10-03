import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../customer/home_screen.dart';
import 'login_screen.dart';
import 'role_home.dart';

/// First screen shown on app launch.
///
/// Coral brand splash with an animated logo and a progress bar that fills
/// over [_minDuration]. Navigates once the bar is full *and* the auth session
/// has settled (capped so a slow network can't trap the user here).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _minDuration = Duration(seconds: 5);
  static const _authCap = Duration(seconds: 8);

  /// Logo / title entrance (first ~1.2s).
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  /// Gentle breathing glow behind the logo.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  /// Loading bar, 0 → 1 over [_minDuration].
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: _minDuration,
  )..forward();

  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final auth = context.read<AuthProvider>();
    final stopwatch = Stopwatch()..start();

    await Future.delayed(_minDuration);
    if (!mounted) return;

    // Wait for the auth session (and profile doc) to settle.
    while (auth.isLoading && stopwatch.elapsed < _authCap) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }
    if (auth.isLoggedIn) {
      while (auth.profile == null && stopwatch.elapsed < _authCap) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
      }
    }
    if (!mounted || _navigated) return;
    _navigated = true;

    final Widget next;
    if (auth.isLoggedIn && auth.profile == null) {
      // Remembered session but no readable profile: don't open Home
      // half-signed-in — sign out and start from Login.
      await auth.signOut();
      if (!mounted) return;
      next = const LoginScreen(notice: profileLoadFailedNotice);
    } else if (auth.isLoggedIn) {
      next = destinationAfterAuth(auth);
    } else if (auth.isGuest) {
      next = const HomeScreen();
    } else {
      next = const LoginScreen();
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, _, _) => next,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  String _statusFor(double t) {
    if (t < 0.35) return 'CONNECTING TO UKAYS';
    if (t < 0.75) return 'LOADING FRESH FINDS';
    return 'ALMOST READY';
  }

  /// Fade + slide-up for an element appearing between [start] and [end]
  /// (fractions of the intro animation).
  Widget _enter(double start, double end, Widget child) {
    final curve = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logoScale = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, 0.6, curve: Curves.easeOutBack),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.coralDeep,
      ),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [AppColors.coralDeep, AppColors.coral],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 5),
                // Logo in a cream disc with a breathing halo.
                ScaleTransition(
                  scale: logoScale,
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      final t = Curves.easeInOut.transform(_pulse.value);
                      return Container(
                        padding: EdgeInsets.all(10 + 6 * t),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.10 + 0.06 * t),
                        ),
                        child: child,
                      );
                    },
                    child: Container(
                      width: 132,
                      height: 132,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.paper,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/swidshop_mark.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.swap_horiz,
                          size: 56,
                          color: AppColors.coral,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _enter(
                  0.35,
                  0.75,
                  const Text(
                    'SwidShop',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _enter(
                  0.5,
                  0.9,
                  Text(
                    'Bid it. Swap it. Sulit ang thrift!',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(flex: 6),
                _enter(
                  0.6,
                  1,
                  AnimatedBuilder(
                    animation: _progress,
                    builder: (context, _) {
                      final t = Curves.easeInOut.transform(_progress.value);
                      return Column(
                        children: [
                          SizedBox(
                            width: 200,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: t,
                                minHeight: 5,
                                color: Colors.white,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              '${_statusFor(t)}...',
                              key: ValueKey(_statusFor(t)),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 56),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
