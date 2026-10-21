import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/screens/auth_gate.dart' show kStayLoggedInKey;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:modal_progress_hud_nsn/modal_progress_hud_nsn.dart';
import 'package:shared_preferences/shared_preferences.dart';
 
class LoginScreen extends StatefulWidget {
  static const id = 'login_screen';
 
  const LoginScreen({super.key});
 
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
 
class _LoginScreenState extends State<LoginScreen> {
  final _auth = FirebaseAuth.instance;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
 
  bool _showSpinner = false;
  bool _hidePassword = true;
  bool _stayLoggedIn = true;
  String _errorMessage = '';
 
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
 
  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      // Newer Firebase projects report a wrong email OR password as
      // 'invalid-credential' (to avoid revealing which accounts exist).
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect email or password';
      case 'invalid-email':
        return 'Invalid email format';
      case 'user-disabled':
        return 'Account disabled';
      case 'too-many-requests':
        return 'Too many attempts — try again later';
      case 'network-request-failed':
        return 'No connection. Check your internet and try again';
      default:
        return e.message ?? 'Login failed (${e.code})';
    }
  }
 
  Future<void> _logIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter email and password');
      return;
    }
 
    setState(() {
      _showSpinner = true;
      _errorMessage = '';
    });
 
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (credential.user == null) {
        if (mounted) setState(() => _errorMessage = 'Login succeeded but no user data');
        return;
      }
 
      // Remember the choice so AuthGate knows what to do next launch.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(kStayLoggedInKey, _stayLoggedIn);
      } catch (e) {
        debugPrint('Could not save stay-signed-in choice: $e');
      }
 
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/homePage');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _errorMessage = _messageFor(e));
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _showSpinner = false);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Login', style: TextStyle(fontSize: 30)),
      ),
      body: ModalProgressHUD(
        inAsyncCall: _showSpinner,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 16),
              Hero(
                tag: 'contractor',
                child: SizedBox(
                  height: 180.0,
                  child: Image.asset('images/contractor.png'),
                ),
              ),
              const SizedBox(height: 32.0),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                textAlign: TextAlign.center,
                decoration: kInputDecoration.copyWith(hintText: 'Enter your email'),
              ),
              const SizedBox(height: 8.0),
              TextField(
                controller: _passwordController,
                obscureText: _hidePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _logIn(),
                textAlign: TextAlign.center,
                decoration: kInputDecoration.copyWith(
                  hintText: 'Enter your password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hidePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _hidePassword = !_hidePassword),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _stayLoggedIn,
                onChanged: (v) => setState(() => _stayLoggedIn = v ?? false),
                title: const Text('Stay signed in on this device'),
                subtitle: const Text(
                  'Opens straight to your account next time. '
                  'Only use this on your own phone.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 16.0),
              MaterialButton(
                onPressed: _logIn,
                color: Colors.grey,
                child: const Text('Log In'),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  const Text("Don't have an account? "),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/registerScreen'),
                    child: const Text('create account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}