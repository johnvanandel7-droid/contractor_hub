import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:contractor_hub/services/firebase_services.dart';

/// Wraps FirebaseAuth's current-user state so widgets can react to
/// login/logout with context.watch<AuthProvider>() instead of poking
/// FirebaseAuth.instance.currentUser directly.
class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<User?>? _authSub;

  User? _user;

  AuthProvider() {
    _user = _auth.currentUser;
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  User? get user => _user;
  bool get isLoggedIn => _user != null;

  // Mirrors FirebaseServices' normalization (trimmed/lowercased email).
  String? get currentEmail => FirebaseServices.instance.currentEmail;
  String? get currentUid => FirebaseServices.instance.currentUid;

  void _onAuthChanged(User? user) {
    _user = user;
    notifyListeners();
  }

  Future<void> signOut() => FirebaseServices.instance.signOut();

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
