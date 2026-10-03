import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/primary_button.dart';
import '../customer/home_screen.dart';
import 'register_screen.dart';
import 'role_home.dart';

/// Email/password + Google sign-in. The app's signed-out root screen.
///
/// On success, routes via [goAfterAuth] and clears the stack so the user
/// never lands back on Login via the back button.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.notice});

  /// Optional message shown once on arrival (e.g. profile failed to load).
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _googleBusy = false;
  String? _emailError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    final notice = widget.notice;
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _snack(notice);
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmail() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _emailError = null;
      _passwordError = null;
    });
    try {
      await context.read<AuthProvider>().signIn(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
          );
      if (mounted) await goAfterAuth(context);
    } catch (e) {
      if (!mounted) return;
      // Inline errors for credential problems; snackbar for anything else.
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'wrong-password':
          case 'invalid-credential':
            setState(() => _passwordError = 'Incorrect email or password.');
          case 'user-not-found':
            setState(() => _emailError = 'No account found for that email.');
          case 'invalid-email':
            setState(() => _emailError = 'That email address is not valid.');
          default:
            _snack(AuthService.messageFor(e));
        }
      } else {
        _snack(AuthService.messageFor(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleBusy = true);
    try {
      final auth = context.read<AuthProvider>();
      final result = await auth.signInWithGoogle();
      if (result == GoogleSignInResult.cancelled || !mounted) return;
      await goAfterAuth(
        context,
        beforeNavigate: () => _showGoogleSuccess(auth, result),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _showGoogleSuccess(
    AuthProvider auth,
    GoogleSignInResult result,
  ) {
    final email = auth.firebaseUser?.email ?? '';
    final isNew = result == GoogleSignInResult.newUser;
    return showSuccessPopup(
      context,
      title: 'Google account connected',
      message: isNew
          ? "Signed in as $email. Let's finish setting up your account."
          : 'Welcome back! Signed in as $email.',
      highlight: email.isEmpty ? null : email,
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.red),
    );
  }

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final sent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Reset password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "We'll email you a link to set a new password.",
              style: TextStyle(color: AppColors.gray),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'you@example.com',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    final email = emailCtrl.text.trim();
    emailCtrl.dispose();
    if (sent != true || !mounted) return;
    if (email.isEmpty) {
      _snack('Enter your email first.');
      return;
    }
    try {
      await context.read<AuthProvider>().sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset link sent to $email.')),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(AuthService.messageFor(e));
    }
  }

  void _browseAsGuest() {
    context.read<AuthProvider>().enterGuest();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final anyBusy = _busy || _googleBusy;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: canPop
          ? AppBar(backgroundColor: AppColors.cream)
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, canPop ? 0 : 32, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset(
                    'assets/images/swidshop_mark.png',
                    height: 44,
                    errorBuilder: (_, _, _) => const SizedBox(height: 44),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppColors.ink,
                        letterSpacing: -0.5,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Log in to bid, swap, and shop ukay finds.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: AppColors.gray,
                  ),
                ),
                const SizedBox(height: 32),
                const FieldLabel('Email address'),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: Validators.email,
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: const Icon(Icons.mail_outline),
                    errorText: _emailError,
                  ),
                  onChanged: (_) {
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                  },
                ),
                const SizedBox(height: 18),
                const FieldLabel('Password'),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: Validators.password,
                  onFieldSubmitted: (_) => anyBusy ? null : _signInWithEmail(),
                  decoration: InputDecoration(
                    hintText: 'Your password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    errorText: _passwordError,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onChanged: (_) {
                    if (_passwordError != null) {
                      setState(() => _passwordError = null);
                    }
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: anyBusy ? null : _forgotPassword,
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  label: 'Log In',
                  loading: _busy,
                  onPressed: anyBusy ? null : _signInWithEmail,
                ),
                const SizedBox(height: 24),
                const LabeledDivider('or'),
                const SizedBox(height: 24),
                GoogleButton(
                  loading: _googleBusy,
                  onPressed: anyBusy ? null : _signInWithGoogle,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account?",
                      style: TextStyle(color: AppColors.gray),
                    ),
                    TextButton(
                      onPressed: anyBusy
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              ),
                      child: const Text(
                        'Register',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (!canPop)
                  Center(
                    child: TextButton(
                      onPressed: anyBusy ? null : _browseAsGuest,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.gray,
                      ),
                      child: const Text('Browse as guest'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
