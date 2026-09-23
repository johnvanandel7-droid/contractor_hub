import 'package:flutter/material.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/components/reusable_button.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final services = FirebaseServices.instance;
  final auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final currentUserUid = auth.currentUser?.uid;

    if (currentUserUid == null) {
      return const Scaffold(body: Center(child: Text('User isn\'t logged in')));
    }

    return Scaffold(
      appBar: AppBarWidget(),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: services.getUser(currentUserUid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              debugPrint(
                'getUser failed for uid $currentUserUid: ${snapshot.error}',
              );
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error loading account: ${snapshot.error}'),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data == null) {
              debugPrint('No user document found for uid: $currentUserUid');
              return const Center(
                child: Text(
                  'Could not load your account (no user document found)',
                ),
              );
            }

            final user = snapshot.data!;
            final userStatus = user['status'] as String?;

            // ── Pending check ──────────────────────────────────────────
            if (userStatus == 'pending') {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'Your account is pending acceptance from the boss',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              );
            }

            // ── Normal home content ────────────────────────────────────
            final bool isEmployee = user['isEmployee'] as bool? ?? true;

            return SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isEmployee) ...[
                    ReusableButton(
                      buttonText: 'Administrator panel',
                      onPress: () {
                        Navigator.pushNamed(context, '/administratorPanel');
                      },
                      buttonHeight: 40,
                      buttonWidth: double.infinity,
                      buttonColor: Colors.yellow,
                      buttonPadding: 8,
                    ),
                  ],
                  ReusableButton(
                    buttonText: 'Clock In / Out',
                    onPress: () {
                      Navigator.pushNamed(context, '/clockInOut');
                    },
                    buttonHeight: 40,
                    buttonWidth: double.infinity,
                    buttonColor: Colors.purple,
                    buttonPadding: 8,
                  ),
                  ReusableButton(
                    buttonText: 'ToDo List',
                    onPress: () {
                      Navigator.pushNamed(context, '/toDoList');
                    },
                    buttonHeight: 40,
                    buttonWidth: double.infinity,
                    buttonColor: Colors.blue,
                    buttonPadding: 8,
                  ),
                  ReusableButton(
                    buttonText: 'Expense tracker',
                    onPress: () {
                      Navigator.pushNamed(context, '/expenseTracker');
                    },
                    buttonHeight: 40,
                    buttonWidth: double.infinity,
                    buttonColor: Colors.blueGrey,
                    buttonPadding: 8,
                  ),
                  ReusableButton(
                    buttonText: 'Construction Images',
                    onPress: () {
                      Navigator.pushNamed(context, '/constructionImages');
                    },
                    buttonHeight: 40,
                    buttonWidth: double.infinity,
                    buttonColor: Colors.blue,
                    buttonPadding: 8,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
