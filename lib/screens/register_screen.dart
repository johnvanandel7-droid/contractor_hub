import 'package:contractor_hub/constants.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:modal_progress_hud_nsn/modal_progress_hud_nsn.dart';

final _firestore = FirebaseFirestore.instance;
final _messaging = FirebaseMessaging.instance;

class RegistrationScreen extends StatefulWidget {
  static const id = 'registration_screen';

  const RegistrationScreen({super.key});
  @override
  // ignore: library_private_types_in_public_api
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool showSpinner = false;
  String? email;
  String? password;
  String? confirmPassword;
  bool allowedEntry = false;
  String deniedEntryReason = '';
  bool agreedToTerms = false;
  bool agreeToEmails = true;

  @override
  void initState() {
    super.initState();
    // Check if this is a free trial registration
    _checkRegistrationMode();
  }

  void _checkRegistrationMode() {
    // Determine if user came from payment (paid) or free trial
    // This can be tracked via navigation arguments
  }

  Future<void> _registerUser() async {
    // Clear previous error
    setState(() {
      deniedEntryReason = '';
      showSpinner = true;
    });

    // Validation checks
    if (email == null ||
        email!.trim().isEmpty ||
        password == null ||
        password!.trim().isEmpty ||
        confirmPassword == null ||
        confirmPassword!.trim().isEmpty) {
      setState(() {
        deniedEntryReason = 'Please fill in all fields';
        showSpinner = false;
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        deniedEntryReason = 'Passwords do not match';
        showSpinner = false;
      });
      return;
    }

    if (password!.length < 6) {
      setState(() {
        deniedEntryReason = 'Password must be at least 6 characters';
        showSpinner = false;
      });
      return;
    }

    if (!_isValidEmail(email!)) {
      setState(() {
        deniedEntryReason = 'Please enter a valid email address';
        showSpinner = false;
      });
      return;
    }

    if (!agreedToTerms) {
      setState(() {
        deniedEntryReason = 'You must agree to the Terms of Service';
        showSpinner = false;
      });
      return;
    }

    try {
      // Create user in Firebase Authentication
      final UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(
            email: email!.trim().toLowerCase(),
            password: password!.trim(),
          );

      final String uid = userCredential.user!.uid;

      // Get FCM token for push notifications
      String? token;
      try {
        token = await _messaging.getToken();
      } catch (e) {
        debugPrint('Error getting FCM token: $e');
      }

      // Create user document in Firestore
      final docRef = _firestore.collection('users').doc(uid);

      final doc = await docRef.get();
      if (!doc.exists) {
        await docRef.set({
          'userId': uid,
          'userEmail': email!.trim().toLowerCase(),
          'displayName': email!.split(
            '@',
          )[0], // Use email prefix as initial name
          'createdAt': FieldValue.serverTimestamp(),
          'phoneToken': token ?? '',
          'isBanned': false,
          'emailPreferences': {
            'marketing': agreeToEmails,
            'orderUpdates': true,
            'messages': true,
          },
          'accountType': 'free_trial', // or 'paid' if registration fee was paid
          'verified': false,
        });
      }

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // Navigate to home
      Navigator.pushNamedAndRemoveUntil(context, 'home_page', (route) => false);
    } on FirebaseAuthException catch (e) {
      String message;

      switch (e.code) {
        case 'weak-password':
          message = 'Password is too weak. Use at least 6 characters.';
          break;
        case 'email-already-in-use':
          message = 'This email is already registered. Try logging in instead.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Please try again later.';
          break;
        case 'operation-not-allowed':
          message = 'Email/password signup is not enabled.';
          break;
        default:
          message = e.message ?? 'Registration failed. Please try again.';
      }

      setState(() => deniedEntryReason = message);
    } catch (e) {
      setState(() => deniedEntryReason = 'Unexpected error: $e');
    } finally {
      if (mounted) {
        setState(() => showSpinner = false);
      }
    }
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('Create Account', style: TextStyle(color: Colors.black)),
      ),
      body: ModalProgressHUD(
        inAsyncCall: showSpinner,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: 20),
                Flexible(
                  child: Hero(
                    tag: 'contractor',
                    child: SizedBox(
                      height: 120.0,
                      child: Image.asset('images/contractor.png'),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Join Contractor Hub',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'track time save construction photos todo list and more',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                // Email field
                const Text(
                  'Email Address',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  keyboardType: TextInputType.emailAddress,
                  textAlign: TextAlign.left,
                  onChanged: (value) {
                    setState(() {
                      email = value;
                    });
                  },
                  decoration: kInputDecoration.copyWith(
                    hintText: 'your.email@example.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),

                // Password field
                const Text(
                  'Password',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  obscureText: true,
                  textAlign: TextAlign.left,
                  onChanged: (value) {
                    setState(() {
                      password = value;
                    });
                  },
                  decoration: kInputDecoration.copyWith(
                    hintText: 'At least 6 characters',
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 16),

                // Confirm Password field
                const Text(
                  'Confirm Password',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  obscureText: true,
                  textAlign: TextAlign.left,
                  onChanged: (value) {
                    setState(() {
                      confirmPassword = value;
                    });
                  },
                  decoration: kInputDecoration.copyWith(
                    hintText: 'Confirm your password',
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 16),

                // Terms checkbox
                Row(
                  children: [
                    Checkbox(
                      value: agreedToTerms,
                      onChanged: (value) {
                        setState(() {
                          agreedToTerms = value ?? false;
                        });
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            agreedToTerms = !agreedToTerms;
                          });
                        },
                        child: Text(
                          'I agree to the Terms of Service and Privacy Policy',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Email preferences checkbox
                Row(
                  children: [
                    Checkbox(
                      value: agreeToEmails,
                      onChanged: (value) {
                        setState(() {
                          agreeToEmails = value ?? false;
                        });
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            agreeToEmails = !agreeToEmails;
                          });
                        },
                        child: Text(
                          'Send me offers and updates about contractor hub',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Error message
                if (deniedEntryReason.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      border: Border.all(color: Colors.red[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      deniedEntryReason,
                      style: TextStyle(color: Colors.red[700], fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 24),

                // Create account button
                MaterialButton(
                  onPressed: _registerUser,
                  color: Colors.blue,
                  child: Text('Create Account'),
                ),
                const SizedBox(height: 16),

                // Login link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        'Log in',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
