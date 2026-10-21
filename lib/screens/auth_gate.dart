
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
 
/// SharedPreferences key: did the person choose "Stay signed in" at login?
const kStayLoggedInKey = 'stay_logged_in';
 
/// First screen of the app. Decides where to go:
///   * saved session + "stay signed in"  -> straight to the home page
///   * saved session but they opted out  -> sign out, go to the welcome screen
///   * no session                        -> welcome screen
///
/// Firebase Auth already saves the session on the device (it keeps a refresh
/// token, never the password), so there is nothing extra to store for the
/// login itself. This widget only reads the person's choice.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
 
  @override
  State<AuthGate> createState() => _AuthGateState();
}
 
class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _route();
  }
 
  Future<void> _route() async {
    var target = '/welcomeScreen';
    try {
      // authStateChanges() fires once Firebase has finished restoring any
      // saved session, so currentUser isn't read too early.
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 5));
 
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        // Anyone who was already signed in before this feature existed has
        // no saved choice yet; treat that as "stay signed in".
        final stay = prefs.getBool(kStayLoggedInKey) ?? true;
        if (stay) {
          target = '/homePage';
        } else {
          await FirebaseAuth.instance.signOut();
        }
      }
    } catch (e) {
      debugPrint('AuthGate: could not restore session: $e');
    }
 
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, target);
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 140,
              child: Image.asset('images/contractor.png'),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
 