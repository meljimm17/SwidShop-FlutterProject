import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/constants.dart';
import '../models/user_model.dart';
import 'firestore_service.dart';

/// Outcome of a Google sign-in attempt.
enum GoogleSignInResult {
  /// Signed in; an existing, fully set-up profile was found.
  signedIn,

  /// Signed in for the first time; profile still needs onboarding.
  newUser,

  /// The user closed the account picker. Not an error.
  cancelled,
}

/// Authentication facade over Firebase Auth (Email/Password + Google).
class AuthService {
  AuthService({FirebaseAuth? auth, FirestoreService? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirestoreService();

  final FirebaseAuth _auth;
  final FirestoreService _firestore;

  static Future<void>? _googleInit;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Registers a new user and writes the full `users/{uid}` profile doc.
  Future<UserCredential> signUpWithEmail({
    required String name,
    required String email,
    required String password,
    String firstName = '',
    String middleName = '',
    String lastName = '',
    UserRole role = UserRole.customer,
    AddressModel? address,
    DateTime? dob,
    String? photoUrl,
    bool profileComplete = true,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user != null) {
      await user.updateDisplayName(name);
      await _firestore.createUserProfile(
        UserModel(
          uid: user.uid,
          name: name,
          firstName: firstName,
          middleName: middleName,
          lastName: lastName,
          email: email.trim(),
          photoUrl: photoUrl ?? '',
          role: role,
          address: address ?? const AddressModel(),
          dob: dob,
          profileComplete: profileComplete,
          createdAt: DateTime.now(),
        ),
      );
    }
    return cred;
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  /// True when [username]/[password] are the admin credentials.
  static bool isAdminLogin(String username, String password) =>
      username.trim().toLowerCase() == AppConstants.adminUsername &&
      password == AppConstants.adminPassword;

  static bool isSuperAdminLogin(String username, String password) =>
      username.trim().toLowerCase() == AppConstants.superAdminUsername &&
      password == AppConstants.superAdminPassword;

  static bool isAdministratorLogin(String username, String password) =>
      isAdminLogin(username, password) || isSuperAdminLogin(username, password);

  /// Administrator login (username + password dialog on the Login screen).
  ///
  /// The demo superadmin account is provisioned on first use. This shared,
  /// source-controlled credential is only suitable for the class demo.
  Future<void> signInAdmin(String username, String password) async {
    if (isSuperAdminLogin(username, password)) {
      await _signInSuperAdmin();
      return;
    }
    if (!isAdminLogin(username, password)) {
      throw const AdminLoginException('Incorrect admin username or password.');
    }
    const email = AppConstants.adminEmail;
    User? user;
    try {
      user = (await _auth.signInWithEmailAndPassword(
        email: email,
        password: AppConstants.adminPassword,
      )).user;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found' &&
          e.code != 'invalid-credential' &&
          e.code != 'wrong-password') {
        rethrow;
      }
    }

    // Existing account on the earlier password: sign in, then migrate.
    if (user == null) {
      try {
        user = (await _auth.signInWithEmailAndPassword(
          email: email,
          password: AppConstants.legacyAdminPassword,
        )).user;
        await user?.updatePassword(AppConstants.adminPassword);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'user-not-found' &&
            e.code != 'invalid-credential' &&
            e.code != 'wrong-password') {
          rethrow;
        }
      }
    }
    // No account yet: provision it.
    if (user == null) {
      try {
        user = (await _auth.createUserWithEmailAndPassword(
          email: email,
          password: AppConstants.adminPassword,
        )).user;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          throw const AdminLoginException(
            'The admin account exists with a different password. Reset it '
            'in the Firebase console.',
          );
        }
        rethrow;
      }
      if (user != null) await user.updateDisplayName('SwidShop Admin');
    }
    if (user == null) {
      throw const AdminLoginException('Admin sign-in failed. Try again.');
    }
    // Make sure the admin profile exists with the admin role.
    final profile = await _firestore.getUser(user.uid);
    if (profile == null) {
      await _firestore.createUserProfile(
        UserModel(
          uid: user.uid,
          name: 'SwidShop Admin',
          email: email,
          role: UserRole.admin,
          createdAt: DateTime.now(),
        ),
      );
    } else if (profile.role != UserRole.admin &&
        profile.role != UserRole.superadmin) {
      await _firestore.updateUserProfile(user.uid, {
        'role': UserRole.admin.value,
      });
    }
  }

  Future<void> _signInSuperAdmin() async {
    const email = AppConstants.superAdminEmail;
    User? user;
    try {
      user = (await _auth.signInWithEmailAndPassword(
        email: email,
        password: AppConstants.superAdminPassword,
      )).user;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found' &&
          e.code != 'invalid-credential' &&
          e.code != 'wrong-password') {
        rethrow;
      }
    }
    if (user == null) {
      try {
        user = (await _auth.createUserWithEmailAndPassword(
          email: email,
          password: AppConstants.superAdminPassword,
        )).user;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use' ||
            e.code == 'invalid-credential' ||
            e.code == 'wrong-password') {
          throw const AdminLoginException(
            'The demo superadmin account exists with a different password. '
            'Contact the Firebase project owner.',
          );
        }
        rethrow;
      }
      if (user != null) await user.updateDisplayName('SwidShop Superadmin');
    }
    if (user == null) {
      throw const AdminLoginException('Superadmin sign-in failed. Try again.');
    }
    try {
      final profile = await _firestore.getUser(user.uid);
      if (profile == null) {
        await _firestore.createUserProfile(
          UserModel(
            uid: user.uid,
            name: 'SwidShop Superadmin',
            email: email,
            role: UserRole.superadmin,
            createdAt: DateTime.now(),
          ),
        );
      } else if (profile.role != UserRole.superadmin) {
        throw const AdminLoginException(
          'The configured superadmin account has an invalid role.',
        );
      }
    } on FirebaseException {
      await _auth.signOut();
      rethrow;
    } on AdminLoginException {
      await _auth.signOut();
      rethrow;
    }
  }

  /// Signs in with Google (google_sign_in 7.x). On first sign-in, creates a
  /// `users/{uid}` doc with `profileComplete: false` so the app routes the
  /// user through the remaining registration steps.
  ///
  /// Android needs the Firebase project's Web OAuth client, which the
  /// google-services plugin exposes as `default_web_client_id` once the app's
  /// SHA-1 is registered and `google-services.json` is re-downloaded.
  Future<GoogleSignInResult> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn.instance;
    await (_googleInit ??= googleSignIn.initialize());

    final GoogleSignInAccount account;
    try {
      account = await googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return GoogleSignInResult.cancelled;
      }
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google did not return an ID token.',
      );
    }
    final cred = await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );

    final user = cred.user;
    if (user == null) return GoogleSignInResult.cancelled;

    final existing = await _firestore.getUser(user.uid);
    if (existing != null) {
      return existing.profileComplete
          ? GoogleSignInResult.signedIn
          : GoogleSignInResult.newUser;
    }

    final displayName = user.displayName ?? account.displayName ?? '';
    final parts = displayName.trim().split(RegExp(r'\s+'));
    await _firestore.createUserProfile(
      UserModel(
        uid: user.uid,
        name: displayName,
        firstName: parts.isNotEmpty ? parts.first : '',
        lastName: parts.length > 1 ? parts.last : '',
        email: user.email ?? account.email,
        photoUrl: user.photoURL ?? account.photoUrl ?? '',
        profileComplete: false,
        createdAt: DateTime.now(),
      ),
    );
    return GoogleSignInResult.newUser;
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Ignore if Google sign-in was never initialised.
    }
    await _auth.signOut();
  }

  /// Translates auth errors into friendly messages.
  static String messageFor(Object error) {
    debugPrint('Auth error: $error');
    if (error is AdminLoginException) return error.message;
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
        case 'missing-email':
        case 'channel-error':
          return 'That email address is not valid.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'user-not-found':
          return 'No account found for that email.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'email-already-in-use':
          return 'An account already exists for that email.';
        case 'weak-password':
          return 'Please choose a stronger password.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'network-request-failed':
          return 'Network error. Check your connection.';
        case 'account-exists-with-different-credential':
          return 'This email is registered with a password. Log in with '
              'email instead.';
        case 'operation-not-allowed':
          return 'Google sign-in is not enabled for this app yet.';
        case 'missing-id-token':
          return 'Google sign-in is not configured for this app yet.';
        default:
          return error.message ?? 'Authentication failed.';
      }
    }
    if (error is GoogleSignInException) {
      switch (error.code) {
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          return 'Google sign-in is not configured for this app yet.';
        case GoogleSignInExceptionCode.uiUnavailable:
          return 'Google sign-in could not open. Try again.';
        default:
          return 'Google sign-in failed (${error.code.name}).';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}

/// Wrong admin username/password, or an admin account problem.
class AdminLoginException implements Exception {
  const AdminLoginException(this.message);

  final String message;

  @override
  String toString() => message;
}
