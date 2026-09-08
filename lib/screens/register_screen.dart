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
  String? password;
  String? confirmPassword;
  String deniedEntryReason = '';
  bool isEmployee = true;
  String? numberOfEmployees;
  TextEditingController companyNameController = TextEditingController();

  // Companies pulled live from Firestore. An "employee" registration is
  // only allowed to pick one of these — never free-text a company name.
  List<Map<String, dynamic>> joinableCompanies = [];
  String? selectedCompanyId;

  String companyPaymentPlan = 'small';
  int numberOfAddableEmployees = 10;
  bool smallPaymentCompany = true;
  bool mediumPaymentCompany = false;
  bool largePaymentCompany = false;

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

    if (!_isValidEmail(email!)) {
      setState(() {
        deniedEntryReason = 'Please enter a valid email address';
        showSpinner = true;
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        deniedEntryReason = 'Passwords do not match';
        showSpinner = true;
      });
      return;
    }

    if (password!.length < 6) {
      setState(() {
        deniedEntryReason = 'Password must be at least 6 characters';
        showSpinner = true;
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

      if (numberOfEmployees != null &&
          numberOfEmployees!.isNotEmpty &&
          int.tryParse(numberOfEmployees!) == null) {
        setState(() {
          deniedEntryReason = 'Please enter a valid number of employees';
          showSpinner = false;
        });
        return;
      }
    }

    try {
      final UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(
            email: email!.trim().toLowerCase(),
            password: password!.trim(),
          );

      final String uid = userCredential.user!.uid;

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
          'numberOfEmployees': 0,
          'numberOfAddableEmployees': numberOfAddableEmployees,
          'companyPaymentPlan': companyPaymentPlan,
          'employeeIds': [],
          'images': [],
        });
        finalCompanyId = newCompanyRef.id;
        finalCompanyName = companyNameController.text.trim();
      }

      final docRef = _firestore.collection('users').doc(uid);
      final doc = await docRef.get();
      if (!doc.exists) {
        await docRef.set({
          'userId': uid,
          'userEmail': email!.trim().toLowerCase(),
          'createdAt': FieldValue.serverTimestamp(),
          'phoneToken': token ?? '',
          'isEmployee': isEmployee,
          'companyId': finalCompanyId,
          'companyName': finalCompanyName,
          if (!isEmployee) 'numberOfEmployees': numberOfEmployees,
        });
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

                Padding(
                  padding: const EdgeInsets.all(10.0),
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
                          child: Text('Employee'),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              isEmployee = false;
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
                          child: Text('Owner/boss'),
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
                              'No companies found. Ask your employer too register first or refresh.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _getJoinableCompanies,
                            icon: Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedCompanyId,
                            decoration: kInputDecoration.copyWith(
                              hintText: 'select your company',
                            ),
                            items: joinableCompanies.map((c) {
                              final current =
                                  (c['numberOfEmployees'] ?? 0) as int;
                              final max =
                                  (c['numberOfAddableEmployees'] ?? 0) as int;
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
                        ),
                      ],
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
                  const SizedBox(height: 16),
                  Text('Number of employees'),
                  TextField(
                    decoration: kInputDecoration.copyWith(
                      hintText: 'number of employees',
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value.isNotEmpty && int.tryParse(value) == null) {
                          deniedEntryReason = 'invalid number of employees';
                        } else {
                          deniedEntryReason = '';
                        }
                        numberOfEmployees = value;
                      });
                    },
                  ),
                  SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: _PlanCard(
                          title: 'Small business',
                          price: '\$20 CAD',
                          description:
                              'Meant for small companies with a max of 10 employees with the app',
                          selected: smallPaymentCompany,
                          onTap: () => setState(() {
                            smallPaymentCompany = true;
                            mediumPaymentCompany = false;
                            largePaymentCompany = false;
                            companyPaymentPlan = 'small';
                            numberOfAddableEmployees = 10;
                          }),
                        ),
                      ),
                      Expanded(
                        child: _PlanCard(
                          title: 'Enterprise',
                          price: '\$40 CAD',
                          description:
                              'Meant for large companies with a max of 100 employees with the app',
                          selected: mediumPaymentCompany,
                          onTap: () => setState(() {
                            smallPaymentCompany = false;
                            mediumPaymentCompany = true;
                            largePaymentCompany = false;
                            companyPaymentPlan = 'medium';
                            numberOfAddableEmployees = 100;
                          }),
                        ),
                      ),
                      Expanded(
                        child: _PlanCard(
                          title: 'Large Enterprise',
                          price: '\$100 CAD',
                          description:
                              'Meant for large companies with unlimited employees',
                          selected: largePaymentCompany,
                          onTap: () => setState(() {
                            smallPaymentCompany = false;
                            mediumPaymentCompany = false;
                            largePaymentCompany = true;
                            companyPaymentPlan = 'large';
                            numberOfAddableEmployees = 1000000000;
                          }),
                        ),
                      ),
                    ],
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
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          decoration: kboxDecoration.copyWith(
            color: selected ? Colors.blue[700] : Colors.blue[400],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(price, style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
