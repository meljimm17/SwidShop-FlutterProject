import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../models/user_private_details_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// Authentication + current-user profile state.
class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? authService, FirestoreService? firestoreService})
      : _auth = authService ?? AuthService(),
        _firestore = firestoreService ?? FirestoreService() {
    _authSub = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  final AuthService _auth;
  final FirestoreService _firestore;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<UserModel?>? _profileSub;

  User? _firebaseUser;
  UserModel? _profile;
  bool _loading = true;
  bool _isGuest = false;

  User? get firebaseUser => _firebaseUser;
  UserModel? get profile => _profile;
  bool get isLoggedIn => _firebaseUser != null;
  bool get isLoading => _loading;

  /// Signed in but registration steps (role, profile, terms) not finished —
  /// e.g. a first-time Google sign-in.
  bool get needsOnboarding =>
      _firebaseUser != null && _profile != null && !_profile!.profileComplete;

  /// True when browsing without an account (Login → Browse as guest).
  /// Used to gate bid/buy/swap and other protected actions.
  bool get isGuest => _isGuest && _firebaseUser == null;

  /// Enters read-only guest mode. Cleared automatically on sign-in/sign-out.
  void enterGuest() {
    _isGuest = true;
    _loading = false;
    notifyListeners();
  }

  void _onAuthStateChanged(User? user) {
    _firebaseUser = user;
    _isGuest = false;
    _profileSub?.cancel();

    if (user == null) {
      _profile = null;
      _loading = false;
      notifyListeners();
      return;
    }

    _profileSub = _firestore.streamUser(user.uid).listen(
      (profile) {
        _profile = profile;
        _loading = false;
        notifyListeners();
      },
      // e.g. permission-denied when deployed rules don't match the app.
      onError: (Object e) {
        debugPrint('Profile stream error: $e');
        _profile = null;
        _loading = false;
        notifyListeners();
      },
    );
  }

  Future<void> signUp({
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
  }) =>
      _auth.signUpWithEmail(
        name: name,
        email: email,
        password: password,
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        role: role,
        address: address,
        dob: dob,
        photoUrl: photoUrl,
        profileComplete: profileComplete,
      );

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordReset(email);

  Future<void> signIn({required String email, required String password}) =>
      _auth.signInWithEmail(email: email, password: password);

  Future<GoogleSignInResult> signInWithGoogle() => _auth.signInWithGoogle();

  Future<void> signOut() => _auth.signOut();

  Future<void> updateProfile(Map<String, dynamic> data) async {
    final uid = _firebaseUser?.uid;
    if (uid == null) return;
    await _firestore.updateUserProfile(uid, data);
  }

  /// Overwrites the signed-in user's full `users/{uid}` doc.
  Future<void> saveProfile(UserModel profile) =>
      _firestore.createUserProfile(profile);

  /// Writes owner-only details (phone, street, ID photos, terms acceptance).
  Future<void> savePrivateDetails(UserPrivateDetails details) async {
    final uid = _firebaseUser?.uid;
    if (uid == null) return;
    await _firestore.saveUserPrivateDetails(uid, details);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
