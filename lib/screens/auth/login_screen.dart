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
  bool _adminBusy = false;
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

  /// Asks for the email in a dialog that owns its controller (disposing a
  /// controller while the dialog is still animating closed throws), then
  /// sends the Firebase reset email.
  Future<void> _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) =>
          _ResetPasswordDialog(initialEmail: _emailCtrl.text.trim()),
    );
    if (email == null || !mounted) return;
    try {
      await context.read<AuthProvider>().sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            'If an account exists for $email, a reset link is on its way. '
            'Check your Spam folder too.',
          ),
        ),
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

  /// Admin login: asks for the admin username + password, then routes by
  /// role like any other sign-in.
  Future<void> _adminLogin() async {
    final creds = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _AdminLoginDialog(),
    );
    if (creds == null || !mounted) return;
    setState(() => _adminBusy = true);
    try {
      await context.read<AuthProvider>().signInAdmin(creds.$1, creds.$2);
      if (mounted) await goAfterAuth(context);
    } catch (e) {
      if (mounted) _snack(AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _adminBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anyBusy = _busy || _googleBusy || _adminBusy;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: canPop ? AppBar(backgroundColor: AppColors.cream) : null,
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
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(color: AppColors.ink, letterSpacing: -0.5),
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
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
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
                if (!canPop)
                  Center(
                    child: TextButton.icon(
                      onPressed: anyBusy ? null : _adminLogin,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.teal,
                      ),
                      icon: _adminBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.admin_panel_settings_outlined,
                              size: 18,
                            ),
                      label: const Text('Login as Administrator'),
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

/// Username + password prompt for administrator accounts. Checks the
/// demo credentials locally first so a typo never reaches Firebase.
class _AdminLoginDialog extends StatefulWidget {
  const _AdminLoginDialog();

  @override
  State<_AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<_AdminLoginDialog> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Enter the username and password.');
      return;
    }
    if (!AuthService.isAdministratorLogin(user, pass)) {
      setState(() => _error = 'Incorrect administrator username or password.');
      return;
    }
    Navigator.of(context).pop((user, pass));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Login as Administrator'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _userCtrl,
            autofocus: true,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.red, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
          child: const Text('Log in'),
        ),
      ],
    );
  }
}

/// Email prompt for the password reset link. Validates the address before
/// returning it; owns (and disposes) its own controller.
class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final _ctrl = TextEditingController(text: widget.initialEmail);
  String? _error;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _ctrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email.');
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = 'That email address is not valid.');
      return;
    }
    Navigator.of(context).pop(email);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
            controller: _ctrl,
            autofocus: widget.initialEmail.isEmpty,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              hintText: 'you@example.com',
              prefixIcon: const Icon(Icons.mail_outline),
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Send link')),
      ],
    );
  }
}
