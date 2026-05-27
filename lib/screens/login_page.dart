import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:modal_progress_hud_nsn/modal_progress_hud_nsn.dart';
import 'package:contractor_hub/constants.dart';

class LoginScreen extends StatefulWidget {
  static const id = 'login_screen';

  const LoginScreen({super.key});
  @override
  // ignore: library_private_types_in_public_api
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final FirebaseAuth _auth;
  bool showSpinner = false;
  String? email;
  String? password;
  String deniedEntryReason2 = '';

  @override
  void initState() {
    super.initState();

    _auth = FirebaseAuth.instance;
  }

  void turnSpinnerOnOff(bool changeSpinner) {
    setState(() {
      showSpinner = changeSpinner;
    });
  }

  void changeErrorMessage(String errorMessage) {
    setState(() {
      deniedEntryReason2 = errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        actions: [],
        title: Text('Login', style: TextStyle(fontSize: 30)),
      ),
      body: ModalProgressHUD(
        inAsyncCall: showSpinner,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Flexible(
                child: Hero(
                  tag: 'contractor',
                  child: SizedBox(
                    height: 200.0,
                    child: Image.asset('images/contractor.png'),
                  ),
                ),
              ),
              SizedBox(height: 48.0),
              TextField(
                keyboardType: TextInputType.emailAddress,
                textAlign: TextAlign.center,
                onChanged: (value) {
                  setState(() {
                    email = value;
                  });
                },
                decoration: kInputDecoration.copyWith(
                  hintText: 'Enter your email',
                ),
              ),
              SizedBox(height: 8.0),
              TextField(
                textAlign: TextAlign.center,
                obscureText: true,
                onChanged: (value) {
                  setState(() {
                    password = value;
                  });
                },
                decoration: kInputDecoration.copyWith(
                  hintText: 'Enter your password',
                ),
              ),
              Text(deniedEntryReason2, style: TextStyle(color: Colors.black)),
              SizedBox(height: 24.0),
              MaterialButton(
                onPressed: () async {
                  turnSpinnerOnOff(true);
                  try {
                    User? user;
                    if (email != null &&
                        email!.trim().isNotEmpty &&
                        password != null &&
                        password!.trim().isNotEmpty) {
                      // safer check

                      final UserCredential credential = await _auth
                          .signInWithEmailAndPassword(
                            email: email!.trim(),
                            password: password!.trim(),
                          );

                      user = credential.user;
                    } else {
                      // Optional: handle empty fields early
                      changeErrorMessage('Please enter email and password');
                      turnSpinnerOnOff(false);
                      return;
                    }

                    if (user != null) {
                      if (!mounted) {
                        // Widget gone — safe exit, no crash
                        turnSpinnerOnOff(false);
                        return;
                      }

                      // Now safe to use context
                      // ignore: use_build_context_synchronously
                      Navigator.pushReplacementNamed(context, 'home_page');

                      turnSpinnerOnOff(false);
                    } else {
                      // Rare: sign-in "succeeded" but no user (edge case)
                      changeErrorMessage('Login succeeded but no user data');
                      turnSpinnerOnOff(false);
                    }
                  } on FirebaseAuthException catch (e) {
                    String message;

                    switch (e.code) {
                      case 'user-not-found':
                        message = 'No account found with this email';
                        break;
                      case 'wrong-password':
                        message = 'Incorrect password';
                        break;
                      case 'invalid-email':
                        message = 'Invalid email format';
                        break;
                      case 'user-disabled':
                        message = 'Account disabled';
                        break;
                      case 'too-many-requests':
                        message = 'Too many attempts — try again later';
                        break;
                      default:
                        message = e.message ?? 'Login failed (${e.code})';
                    }

                    if (mounted) {
                      // Also protect setState
                      changeErrorMessage(message);
                    }
                    turnSpinnerOnOff(false);
                  } catch (e) {
                    if (mounted) {
                      changeErrorMessage('Unexpected error: $e');
                    }
                    turnSpinnerOnOff(false);
                  }
                },
                color: Colors.grey,
                child: Text('Log In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
