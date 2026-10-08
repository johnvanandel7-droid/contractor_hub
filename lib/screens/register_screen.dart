import 'package:contractor_hub/constants.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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
  bool loadingCompanies = true;
  String? email;
  String? name;
  String? password;
  String? confirmPassword;
  String deniedEntryReason = '';
  bool isEmployee = true;
  TextEditingController companyNameController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Companies pulled live from Firestore. An "employee" registration is
  // only allowed to pick one of these — never free-text a company name.
  List<Map<String, dynamic>> joinableCompanies = [];
  String? selectedCompanyId;

  String companyPaymentPlan = 'small';
  int numberOfAddableEmployees = 10;
  bool smallPaymentCompany = true;
  bool mediumPaymentCompany = false;
  bool largePaymentCompany = false;
  int numberOfAddableImages = 100;

  bool get _passwordsMismatch =>
      confirmPassword != null &&
      confirmPassword!.isNotEmpty &&
      password != confirmPassword;

  @override
  void initState() {
    super.initState();
    _getJoinableCompanies();
  }

  @override
  void dispose() {
    companyNameController.dispose();
    super.dispose();
  }

  Future<void> _getJoinableCompanies() async {
    setState(() => loadingCompanies = true);
    try {
      final companySnapshots = await _firestore.collection('companies').get();

      // convert documents into list of  maps
      final companies = companySnapshots.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();

      if (!mounted) return;
      setState(() {
        joinableCompanies = companies;
        loadingCompanies = false;
      });
    } catch (e) {
      debugPrint('Error loading companies: $e');
      if (!mounted) return;
      setState(() {
        joinableCompanies = [];
        loadingCompanies = false;
      });
    }
  }

  Future<void> _registerUser() async {
    setState(() {
      deniedEntryReason = '';
      showSpinner = true;
    });

    // --- Basic field validation ---
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

    if (name == null || name!.trim().isEmpty) {
      setState(() {
        deniedEntryReason = 'Please enter your name';
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

    Map<String, dynamic>? selectedCompany;

    if (isEmployee) {
      // Employee must pick a real, existing company that still has room.
      if (selectedCompanyId == null) {
        setState(() {
          deniedEntryReason = 'Please select the company you work for';
          showSpinner = false;
        });
        return;
      }

      final matches = joinableCompanies.where(
        (c) => c['id'] == selectedCompanyId,
      );
      if (matches.isEmpty) {
        setState(() {
          deniedEntryReason =
              'That company could not be found. Please refresh and try again.';
          showSpinner = false;
        });
        return;
      }
      selectedCompany = matches.first;

      final currentEmployees =
          (selectedCompany['numberOfEmployees'] ?? 0) as int;
      final maxEmployees =
          (selectedCompany['numberOfAddableEmployees'] ?? 0) as int;

      if (currentEmployees >= maxEmployees) {
        setState(() {
          deniedEntryReason =
              'This company has reached its employee limit. Ask the owner to upgrade their plan.';
          showSpinner = false;
        });
        return;
      }
    } else {
      // Owner/foreman is creating a brand new company.
      if (companyNameController.text.trim().isEmpty) {
        setState(() {
          deniedEntryReason = 'Please enter a company name';
          showSpinner = false;
        });
        return;
      }

      final nameToCheck = companyNameController.text.trim().toLowerCase();
      final alreadyExists = joinableCompanies.any(
        (c) =>
            (c['companyName'] ?? '').toString().trim().toLowerCase() ==
            nameToCheck,
      );
      if (alreadyExists) {
        setState(() {
          deniedEntryReason =
              'A company with that name already exists. Choose a different name or join it as an employee.';
          showSpinner = false;
        });
        return;
      }
    }

    UserCredential? userCredential;
    try {
      userCredential = await _auth.createUserWithEmailAndPassword(
        email: email!.trim().toLowerCase(),
        password: password!.trim(),
      );

      final String uid = userCredential.user!.uid;

      try {
        String? token;
        try {
          token = await _messaging.getToken();
        } catch (e) {
          debugPrint('Error getting FCM token: $e');
        }

        late final String finalCompanyId;
        late final String finalCompanyName;

        if (isEmployee) {
          finalCompanyId = selectedCompany!['id'] as String;
          finalCompanyName = selectedCompany['companyName'] as String;

          // Bump the employee count inside a transaction so two people
          // joining at the same moment can't both slip past the limit.
          final companyRef = _firestore
              .collection('companies')
              .doc(finalCompanyId);
          await _firestore.runTransaction((transaction) async {
            final snapshot = await transaction.get(companyRef);
            if (!snapshot.exists) {
              throw Exception('That company no longer exists.');
            }
            final current = (snapshot.data()?['numberOfEmployees'] ?? 0) as int;
            final max =
                (snapshot.data()?['numberOfAddableEmployees'] ?? 0) as int;
            if (current >= max) {
              throw Exception('This company has reached its employee limit.');
            }
            transaction.update(companyRef, {
              'numberOfEmployees': current + 1,
              'employeeIds': FieldValue.arrayUnion([uid]),
            });
          });
        } else {
          final newCompanyRef = await _firestore.collection('companies').add({
            'companyName': companyNameController.text.trim(),
            'bossId': uid,
            'createdAt': FieldValue.serverTimestamp(),

            // employee quota
            'numberOfEmployees': 0,
            'numberOfAddableEmployees': numberOfAddableEmployees,

            // Plan
            'companyPaymentPlan': companyPaymentPlan,

            // Image Quota
            'numberOfAddableImages': numberOfAddableImages,

            // employees
            'employeeIds': [],

            // company images
            'images': [],
          });
          finalCompanyId = newCompanyRef.id;
          finalCompanyName = companyNameController.text.trim();
        }

        final docRef = _firestore.collection('users').doc(uid);
        final doc = await docRef.get();
        if (!doc.exists) {
          await docRef.set({
            if (isEmployee) 'status': 'pending',
            'userId': uid,
            'userEmail': email!.trim().toLowerCase(),
            'createdAt': FieldValue.serverTimestamp(),
            'phoneToken': token ?? '',
            'isEmployee': isEmployee,
            'companyId': finalCompanyId,
            'companyName': finalCompanyName,
            'name': name!.trim(),
          });
        }
      } catch (innerError) {
        // Auth account exists but the company/profile writes above failed
        // partway through — roll it back rather than leaving a login that
        // can never load a profile (home_page.dart has no recovery path
        // for a user doc that never got created).
        try {
          await userCredential.user?.delete();
        } catch (_) {
          // Best effort; if this also fails there's nothing more to do here.
        }
        rethrow;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      Navigator.pushNamedAndRemoveUntil(context, '/homePage', (route) => false);
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code}');
      debugPrint('error Message: ${e.message}');
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
    } catch (e, stack) {
      debugPrint('Unexpected error: $e');
      debugPrint('Stack trace: $stack');
      setState(
        () => deniedEntryReason = e.toString().replaceFirst('Exception: ', ''),
      );
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
        title: const Text(
          'Create Account',
          style: TextStyle(color: Colors.black),
        ),
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
                Hero(
                  tag: 'contractor',
                  child: SizedBox(
                    height: 120.0,
                    child: Image.asset('images/contractor.png'),
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
                  obscureText: _obscurePassword,
                  textAlign: TextAlign.left,
                  onChanged: (value) {
                    setState(() {
                      password = value;
                    });
                  },
                  decoration: kInputDecoration.copyWith(
                    hintText: 'At least 6 characters',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
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
                  obscureText: _obscureConfirmPassword,
                  textAlign: TextAlign.left,
                  onChanged: (value) {
                    setState(() {
                      confirmPassword = value;
                    });
                  },
                  decoration: kInputDecoration.copyWith(
                    hintText: 'Confirm your password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () => setState(
                        () =>
                            _obscureConfirmPassword = !_obscureConfirmPassword,
                      ),
                    ),
                  ),
                ),
                if (_passwordsMismatch)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Passwords don\'t match',
                      style: TextStyle(fontSize: 12, color: Colors.red[700]),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Name',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 20),
                  child: TextField(
                    decoration: kInputDecoration.copyWith(hintText: 'John Doe'),
                    onChanged: (value) {
                      setState(() {
                        name = value;
                      });
                    },
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              isEmployee = true;
                              deniedEntryReason = '';
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isEmployee
                                ? Colors.blue
                                : Colors.grey[300],
                            foregroundColor: isEmployee
                                ? Colors.white
                                : Colors.black87,
                          ),
                          child: const Text('Employee'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              isEmployee = false;
                              deniedEntryReason = '';
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: !isEmployee
                                ? Colors.blue
                                : Colors.grey[300],
                            foregroundColor: !isEmployee
                                ? Colors.white
                                : Colors.black87,
                          ),
                          child: const Text('Owner/boss'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isEmployee) ...[
                  const Text(
                    'Company',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (loadingCompanies)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (joinableCompanies.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'No companies found. Ask your employer to register first, or refresh.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _getJoinableCompanies,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: selectedCompanyId,
                      decoration: kInputDecoration.copyWith(
                        hintText: 'select your company',
                      ),
                      items: joinableCompanies.map((c) {
                        final current = (c['numberOfEmployees'] ?? 0) as int;
                        final max = (c['numberOfAddableEmployees'] ?? 0) as int;
                        final full = current >= max;
                        return DropdownMenuItem<String>(
                          value: c['id'] as String,
                          enabled: !full,
                          child: Text(
                            full
                                ? '${c['companyName']} (full)'
                                : '${c['companyName']}',
                            style: TextStyle(
                              color: full ? Colors.grey : Colors.black,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() {
                        selectedCompanyId = value;
                      }),
                    ),
                  const SizedBox(height: 16),
                ],
                // ---- Owner: creating a brand new company ----
                if (!isEmployee) ...[
                  const Text(
                    'Company name',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: companyNameController,
                    decoration: kInputDecoration.copyWith(
                      hintText: 'company name',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Choose a plan',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  _PlanCard(
                    title: 'Small business',
                    price: '\$20 CAD',
                    description: 'Up to 10 employees 500 addable images',
                    selected: smallPaymentCompany,
                    onTap: () => setState(() {
                      smallPaymentCompany = true;
                      mediumPaymentCompany = false;
                      largePaymentCompany = false;
                      companyPaymentPlan = 'small';
                      numberOfAddableEmployees = 10;
                      numberOfAddableImages = 500;
                    }),
                  ),
                  const SizedBox(height: 10),
                  _PlanCard(
                    title: 'Enterprise',
                    price: '\$40 CAD',
                    description: 'Up to 100 employees 1500 addable images',
                    selected: mediumPaymentCompany,
                    onTap: () => setState(() {
                      smallPaymentCompany = false;
                      mediumPaymentCompany = true;
                      largePaymentCompany = false;
                      companyPaymentPlan = 'medium';
                      numberOfAddableEmployees = 100;
                      numberOfAddableImages = 1500;
                    }),
                  ),
                  const SizedBox(height: 10),
                  _PlanCard(
                    title: 'Large Enterprise',
                    price: '\$100 CAD',
                    description: 'Unlimited employees Unlimited images',
                    selected: largePaymentCompany,
                    onTap: () => setState(() {
                      smallPaymentCompany = false;
                      mediumPaymentCompany = false;
                      largePaymentCompany = true;
                      companyPaymentPlan = 'large';
                      numberOfAddableEmployees = 1000000000;
                      numberOfAddableImages = 100000;
                    }),
                  ),
                ],
                SizedBox(height: 20),
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
                ElevatedButton(
                  onPressed: showSpinner ? null : _registerUser,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    isEmployee
                        ? 'Send request to join company'
                        : 'Create company',
                  ),
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
                      onTap: () => Navigator.pushNamed(context, '/loginPage'),
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
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? Colors.blue[50] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.blue : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? Colors.blue : Colors.grey[400],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.blue : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
