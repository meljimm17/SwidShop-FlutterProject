import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/user_model.dart';
import '../../models/user_private_details_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/primary_button.dart';
import 'role_home.dart';
import 'terms_content.dart';

/// Four-step registration: account → role → profile & ID → terms.
///
/// [RegisterScreen.completeProfile] is used for a signed-in user whose
/// profile is unfinished (first Google sign-in): step 1 then only asks for
/// name and birth date.
///
/// Email sign-ups create the auth account and a `profileComplete: false`
/// doc on submit, then upload photos and private details, and only then
/// flip `profileComplete` — so an interrupted sign-up resumes here.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key}) : completingProfile = false;

  const RegisterScreen.completeProfile({super.key}) : completingProfile = true;

  final bool completingProfile;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _stepNames = ['Account', 'Role', 'Profile', 'Terms'];
  static const _minAge = 18;

  final _accountFormKey = GlobalKey<FormState>();
  final _profileFormKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  // Step 1
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  DateTime? _dob;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _emailError;

  // Step 2
  UserRole _role = UserRole.both;

  // Step 3
  final _phoneCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  File? _photo;
  GovIdType _idType = GovIdType.nationalId;
  File? _idFront;
  File? _idBack;
  bool _showIdErrors = false;

  // Step 4
  bool _acceptTerms = false;
  bool _confirmTruthful = false;

  // Uploaded URLs are cached so a retry after a failure doesn't re-upload.
  String? _photoUrl;
  String? _idFrontUrl;
  String? _idBackUrl;

  int _step = 0;
  bool _busy = false;
  bool _googleBusy = false;
  late bool _completing = widget.completingProfile;

  @override
  void initState() {
    super.initState();
    if (_completing) _prefillFromProfile();
  }

  @override
  void dispose() {
    for (final c in [
      _firstNameCtrl,
      _middleNameCtrl,
      _lastNameCtrl,
      _emailCtrl,
      _passwordCtrl,
      _confirmCtrl,
      _dobCtrl,
      _phoneCtrl,
      _streetCtrl,
      _cityCtrl,
      _provinceCtrl,
      _zipCtrl,
    ]) {
      c.dispose();
    }
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _prefillFromProfile() {
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    _emailCtrl.text = profile?.email ?? auth.firebaseUser?.email ?? '';
    if (profile == null) return;
    if (_firstNameCtrl.text.isEmpty) _firstNameCtrl.text = profile.firstName;
    if (_lastNameCtrl.text.isEmpty) _lastNameCtrl.text = profile.lastName;
    _middleNameCtrl.text = profile.middleName;
    if (profile.dob != null) _setDob(profile.dob!);
  }

  void _setDob(DateTime dob) {
    _dob = dob;
    _dobCtrl.text = AppUtils.formatDate(dob);
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
  }

  void _next() {
    switch (_step) {
      case 0:
        if (!(_accountFormKey.currentState?.validate() ?? false)) return;
      case 2:
        final formOk = _profileFormKey.currentState?.validate() ?? false;
        setState(() => _showIdErrors = true);
        if (!formOk || !_idComplete) return;
    }
    _goTo(_step + 1);
  }

  Future<void> _back() async {
    if (_busy) return;
    if (_step > 0) {
      _goTo(_step - 1);
      return;
    }
    if (!_completing) {
      Navigator.of(context).pop();
      return;
    }
    // A Google user who hasn't finished registration: leaving = sign out.
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Stop signing up?'),
        content: const Text(
          "You'll be signed out. You can finish setting up your account "
          'the next time you continue with Google.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) await signOutToLogin(context);
  }

  bool get _idComplete =>
      _idFront != null && (!_idType.hasBack || _idBack != null);

  // ---------------------------------------------------------------------------
  // Pickers
  // ---------------------------------------------------------------------------

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final latest = DateTime(now.year - _minAge, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: latest,
      helpText: 'Date of birth',
    );
    if (picked != null && mounted) setState(() => _setDob(picked));
  }

  Future<File?> _pickImage({required String title}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return null;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    return picked == null ? null : File(picked.path);
  }

  Future<void> _pickPhoto() async {
    final file = await _pickImage(title: 'Profile photo');
    if (file != null && mounted) {
      setState(() {
        _photo = file;
        _photoUrl = null;
      });
    }
  }

  Future<void> _pickId({required bool front}) async {
    final file = await _pickImage(
      title: front ? 'Front of your ID' : 'Back of your ID',
    );
    if (file == null || !mounted) return;
    setState(() {
      if (front) {
        _idFront = file;
        _idFrontUrl = null;
      } else {
        _idBack = file;
        _idBackUrl = null;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Google (step 1)
  // ---------------------------------------------------------------------------

  Future<void> _continueWithGoogle() async {
    setState(() => _googleBusy = true);
    final auth = context.read<AuthProvider>();
    try {
      final result = await auth.signInWithGoogle();
      if (!mounted) return;
      switch (result) {
        case GoogleSignInResult.cancelled:
          break;
        case GoogleSignInResult.signedIn:
          // Already has a finished account — just log them in.
          await goAfterAuth(
            context,
            beforeNavigate: () => _showGoogleSuccess(
              auth,
              'Welcome back! Signed in as ',
              '.',
            ),
          );
        case GoogleSignInResult.newUser:
          await _waitForProfile(auth);
          if (!mounted) return;
          if (auth.profile == null) {
            // Signed in with Google but the profile couldn't be read/created.
            await auth.signOut();
            if (mounted) _snack(profileLoadFailedNotice);
            return;
          }
          await _showGoogleSuccess(
            auth,
            'Signed in as ',
            ". Let's finish setting up your account.",
          );
          if (!mounted) return;
          setState(() {
            _completing = true;
            _prefillFromProfile();
          });
      }
    } catch (e) {
      if (mounted) _snack(AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _showGoogleSuccess(
    AuthProvider auth,
    String before,
    String after,
  ) {
    final email = auth.firebaseUser?.email ?? '';
    return showSuccessPopup(
      context,
      title: 'Google account connected',
      message: '$before$email$after',
      highlight: email.isEmpty ? null : email,
    );
  }

  Future<void> _waitForProfile(AuthProvider auth) async {
    final stopwatch = Stopwatch()..start();
    while (auth.profile == null &&
        stopwatch.elapsed < const Duration(seconds: 5)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // ---------------------------------------------------------------------------
  // Submit (step 4)
  // ---------------------------------------------------------------------------

  String get _displayName =>
      '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();

  AddressModel get _address => AddressModel(
        city: _cityCtrl.text.trim(),
        province: _provinceCtrl.text.trim(),
        zipCode: _zipCtrl.text.trim(),
        country: 'Philippines',
      );

  Future<void> _submit() async {
    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    try {
      // 1. Auth account (email flow only; skipped on retry / Google).
      if (!auth.isLoggedIn) {
        try {
          await auth.signUp(
            name: _displayName,
            firstName: _firstNameCtrl.text.trim(),
            middleName: _middleNameCtrl.text.trim(),
            lastName: _lastNameCtrl.text.trim(),
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
            role: _role,
            address: _address,
            dob: _dob,
            profileComplete: false,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use' || e.code == 'invalid-email') {
            if (!mounted) return;
            setState(() => _emailError = AuthService.messageFor(e));
            _goTo(0);
            return;
          }
          rethrow;
        }
      }
      final user = auth.firebaseUser;
      if (user == null) throw StateError('Not signed in after sign-up.');
      final uid = user.uid;

      // 2. Images → Cloudinary (only the secure_url is stored).
      final storage = StorageService();
      if (_photo != null) {
        _photoUrl ??= await storage.uploadAvatar(_photo!, uid);
      }
      _idFrontUrl ??= await storage.uploadAvatar(_idFront!, uid);
      if (_idType.hasBack && _idBack != null) {
        _idBackUrl ??= await storage.uploadAvatar(_idBack!, uid);
      }

      // 3. Owner-only details.
      final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
      await auth.savePrivateDetails(
        UserPrivateDetails(
          phone: '+63$digits',
          street: _streetCtrl.text.trim(),
          idType: _idType,
          idFrontUrl: _idFrontUrl ?? '',
          idBackUrl: _idType.hasBack ? (_idBackUrl ?? '') : '',
          termsVersion: AppConstants.termsVersion,
          termsAcceptedAt: DateTime.now(),
        ),
      );

      // 4. Full public profile, marked complete last.
      final existing = auth.profile;
      await auth.saveProfile(
        UserModel(
          uid: uid,
          name: _displayName,
          firstName: _firstNameCtrl.text.trim(),
          middleName: _middleNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          email: user.email ?? _emailCtrl.text.trim(),
          photoUrl: _photoUrl ?? existing?.photoUrl ?? user.photoURL ?? '',
          role: _role,
          address: _address,
          dob: _dob,
          avgRating: existing?.avgRating ?? 0,
          completedTransactions: existing?.completedTransactions ?? 0,
          completionRate: existing?.completionRate ?? 0,
          trustedBadge: existing?.trustedBadge ?? false,
          // Full overwrite: carry server-managed state over unchanged.
          accountStatus: existing?.accountStatus ?? AccountStatus.active,
          plan: existing?.plan ?? 'free',
          planUntil: existing?.planUntil,
          boostedUntil: existing?.boostedUntil,
          favorites: existing?.favorites ?? const [],
          following: existing?.following ?? const [],
          profileComplete: true,
          createdAt: existing?.createdAt ?? DateTime.now(),
        ),
      );
      if (user.displayName != _displayName) {
        await user.updateDisplayName(_displayName);
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => homeForRole(_role)),
        (_) => false,
      );
    } catch (e) {
      if (mounted) _snack(_errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(Object e) {
    if (e is StorageException) return 'Photo upload failed: ${e.message}';
    if (e is FirebaseAuthException) return AuthService.messageFor(e);
    if (e is FirebaseException && e.code == 'permission-denied') {
      debugPrint('Register: $e');
      return "Couldn't save your details (permission denied). "
          'Please try again later.';
    }
    return AuthService.messageFor(e);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.red),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isLast = _step == _stepNames.length - 1;
    final canFinish = _acceptTerms && _confirmTruthful;

    return PopScope(
      canPop: _step == 0 && !_completing && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(
          backgroundColor: AppColors.cream,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy ? null : _back,
          ),
          title: Text(_completing ? 'Finish sign-up' : 'Create account'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: StepProgress(
                  step: _step + 1,
                  total: _stepNames.length,
                  label: _stepNames[_step],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: switch (_step) {
                        0 => _accountStep(),
                        1 => _roleStep(),
                        2 => _profileStep(),
                        _ => _termsStep(),
                      },
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                decoration: const BoxDecoration(
                  color: AppColors.cream,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PrimaryButton(
                      label: isLast ? 'Create account' : 'Continue',
                      icon: isLast ? null : Icons.arrow_forward,
                      loading: _busy,
                      onPressed: _busy || _googleBusy
                          ? null
                          : isLast
                              ? (canFinish ? _submit : null)
                              : _next,
                    ),
                    if (_step == 0 && !_completing)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Already have an account?',
                            style: TextStyle(color: AppColors.gray),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _back,
                            child: const Text(
                              'Log in',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.ink,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
              color: AppColors.gray,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 — account
  // ---------------------------------------------------------------------------

  Widget _accountStep() {
    return Form(
      key: _accountFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            _completing ? 'A few details first' : 'Start thrifting & swapping',
            _completing
                ? 'Confirm your name and add your birth date.'
                : 'Create your account to buy, bid on, and swap '
                    'pre-loved finds.',
          ),
          if (!_completing) ...[
            GoogleButton(
              loading: _googleBusy,
              onPressed: _busy ? null : _continueWithGoogle,
            ),
            const SizedBox(height: 20),
            const LabeledDivider('or sign up with email'),
            const SizedBox(height: 20),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FieldLabel('First name'),
                    TextFormField(
                      controller: _firstNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.givenName],
                      validator: (v) => Validators.required(v, 'First name'),
                      decoration: const InputDecoration(hintText: 'Juan'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FieldLabel('Last name'),
                    TextFormField(
                      controller: _lastNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.familyName],
                      validator: (v) => Validators.required(v, 'Last name'),
                      decoration: const InputDecoration(hintText: 'Dela Cruz'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const FieldLabel('Middle name', trailing: 'Optional'),
          TextFormField(
            controller: _middleNameCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.middleName],
            decoration: const InputDecoration(hintText: 'Santos'),
          ),
          const SizedBox(height: 18),
          const FieldLabel('Email address'),
          TextFormField(
            controller: _emailCtrl,
            readOnly: _completing,
            enabled: !_completing,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            validator: _completing ? null : Validators.email,
            onChanged: (_) {
              if (_emailError != null) setState(() => _emailError = null);
            },
            decoration: InputDecoration(
              hintText: 'you@example.com',
              prefixIcon: const Icon(Icons.mail_outline),
              errorText: _emailError,
              suffixIcon: _completing
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: GoogleLogo(size: 16),
                    )
                  : null,
            ),
          ),
          if (!_completing) ...[
            const SizedBox(height: 18),
            const FieldLabel('Password'),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              validator: Validators.newPassword,
              decoration: InputDecoration(
                hintText: 'At least 8 characters',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const FieldLabel('Confirm password'),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm your password';
                if (v != _passwordCtrl.text) return 'Passwords do not match';
                return null;
              },
              decoration: InputDecoration(
                hintText: 'Re-enter password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          const FieldLabel('Date of birth', trailing: '18+ only'),
          TextFormField(
            controller: _dobCtrl,
            readOnly: true,
            onTap: _pickDob,
            validator: (_) {
              if (_dob == null) return 'Date of birth is required';
              if (!Validators.isAtLeastAge(_dob!, _minAge)) {
                return 'You must be at least $_minAge to join';
              }
              return null;
            },
            decoration: const InputDecoration(
              hintText: 'Select date',
              prefixIcon: Icon(Icons.calendar_today_outlined, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2 — role
  // ---------------------------------------------------------------------------

  Widget _roleStep() {
    Widget option(UserRole role, IconData icon, String title, String desc) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SelectableCard(
          icon: icon,
          title: title,
          description: desc,
          selected: _role == role,
          onTap: () => setState(() => _role = role),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'How will you use SwidShop?',
          'This sets what your home screen shows first.',
        ),
        option(
          UserRole.customer,
          Icons.shopping_bag_outlined,
          'Customer',
          'Browse listings, place bids, buy, and send swap offers.',
        ),
        option(
          UserRole.both,
          Icons.storefront_outlined,
          'Customer + Seller',
          'Everything a customer can do, plus your own shop: post items '
              'for a fixed price, an auction, or a swap.',
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 3 — profile, address, ID
  // ---------------------------------------------------------------------------

  Widget _profileStep() {
    return Form(
      key: _profileFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            'Profile & address',
            'Used for meet-ups and courier pickups. Only your city is shown '
                'on your public profile.',
          ),
          Center(child: _avatarPicker()),
          const SizedBox(height: 28),
          const _SectionTitle('Contact'),
          const FieldLabel('Mobile number'),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            validator: Validators.phMobile,
            decoration: const InputDecoration(
              hintText: '917 123 4567',
              prefixIcon: Padding(
                padding: EdgeInsets.only(left: 16, right: 8),
                child: Text(
                  '+63',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
          const SizedBox(height: 18),
          const FieldLabel('Street address'),
          TextFormField(
            controller: _streetCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.streetAddressLine1],
            validator: (v) => Validators.required(v, 'Street address'),
            decoration: const InputDecoration(
              hintText: 'Unit / house no., street, barangay',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeled(
                  'City / municipality',
                  TextFormField(
                    controller: _cityCtrl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.addressCity],
                    validator: (v) => Validators.required(v, 'City'),
                    decoration: const InputDecoration(hintText: 'Quezon City'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _labeled(
                  'Province / region',
                  TextFormField(
                    controller: _provinceCtrl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.addressState],
                    validator: (v) => Validators.required(v, 'Province'),
                    decoration: const InputDecoration(hintText: 'Metro Manila'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeled(
                  'Postal code',
                  TextFormField(
                    controller: _zipCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.postalCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    validator: Validators.phPostalCode,
                    decoration: const InputDecoration(hintText: '1101'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _labeled(
                  'Country',
                  TextFormField(
                    initialValue: 'Philippines',
                    enabled: false,
                    decoration: const InputDecoration(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const _SectionTitle('Government ID'),
          const Text(
            'Helps keep buyers and sellers safe. Pick the ID you will '
            'upload.',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.gray),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in GovIdType.values)
                ChoiceChip(
                  label: Text(type.label),
                  selected: _idType == type,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _idType = type),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _idType == type ? Colors.white : AppColors.ink,
                  ),
                  selectedColor: AppColors.ink,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                    color: _idType == type ? AppColors.ink : AppColors.line,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _IdUploadTile(
            title: _idType.hasBack ? 'Front of ID' : 'Photo page',
            subtitle: 'Name, photo, and birth date clearly visible',
            icon: Icons.badge_outlined,
            file: _idFront,
            showError: _showIdErrors && _idFront == null,
            onTap: _busy ? null : () => _pickId(front: true),
          ),
          if (_idType.hasBack) ...[
            const SizedBox(height: 12),
            _IdUploadTile(
              title: 'Back of ID',
              subtitle: 'Signature and barcode readable',
              icon: Icons.flip_outlined,
              file: _idBack,
              showError: _showIdErrors && _idBack == null,
              onTap: _busy ? null : () => _pickId(front: false),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.mist.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 18, color: AppColors.teal),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your ID, phone number, and street address are only '
                    'visible to you and SwidShop admins. They never appear '
                    'on your profile or listings.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeled(String label, Widget field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [FieldLabel(label), field],
      );

  Widget _avatarPicker() {
    final networkUrl = context.read<AuthProvider>().profile?.photoUrl ?? '';
    final ImageProvider? image = _photo != null
        ? FileImage(_photo!)
        : (networkUrl.isNotEmpty ? NetworkImage(networkUrl) : null);

    return GestureDetector(
      onTap: _busy ? null : _pickPhoto,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: AppColors.mist,
                backgroundImage: image,
                child: image == null
                    ? const Icon(
                        Icons.person_outline,
                        size: 40,
                        color: AppColors.gray,
                      )
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.coral,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cream, width: 3),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            image == null ? 'Add profile photo' : 'Change photo',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const Text(
            'Optional',
            style: TextStyle(fontSize: 12, color: AppColors.gray),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 4 — terms
  // ---------------------------------------------------------------------------

  Widget _termsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Terms & conditions',
          'Last step. Please read these before creating your account.',
        ),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                termsIntro,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.ink,
                ),
              ),
              for (final section in termsSections) ...[
                const SizedBox(height: 18),
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                for (final point in section.points)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 8, right: 10),
                          child: CircleAvatar(
                            radius: 2,
                            backgroundColor: AppColors.gray,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            point,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.5,
                              color: Color(0xFF55534E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                'Version ${AppConstants.termsVersion}',
                style: const TextStyle(fontSize: 12, color: AppColors.gray),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CheckRow(
          value: _acceptTerms,
          onChanged: (v) => setState(() => _acceptTerms = v),
          text: 'I have read and agree to the SwidShop Terms & Conditions, '
              'including how my data is used.',
        ),
        _CheckRow(
          value: _confirmTruthful,
          onChanged: (v) => setState(() => _confirmTruthful = v),
          text: 'I am at least 18 years old and the details and ID I '
              'provided are true and my own.',
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

class _IdUploadTile extends StatelessWidget {
  const _IdUploadTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.file,
    required this.showError,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final File? file;
  final bool showError;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final done = file != null;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: showError ? AppColors.red : AppColors.line,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 64,
                  height: 44,
                  color: AppColors.cream,
                  child: done
                      ? Image.file(file!, fit: BoxFit.cover)
                      : Icon(icon, color: AppColors.gray),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      showError ? 'Required' : subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: showError ? AppColors.red : AppColors.gray,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              done
                  ? const Icon(Icons.check_circle, color: AppColors.green)
                  : const Text(
                      'Upload',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.coral,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.value,
    required this.onChanged,
    required this.text,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String text;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppColors.coral,
                side: const BorderSide(color: AppColors.gray, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
