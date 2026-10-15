import 'package:contractor_hub/components/admin_card.dart';
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
            final userName = user['name'] as String?;

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
                  Padding(
                    padding: EdgeInsets.fromLTRB(35, 5, 35, 5),
                    child: Text(
                      'Hi $userName',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.05,
                    children: [
                      if (!isEmployee) ...[
                        AdminCard(
                          icon: Icons.admin_panel_settings,
                          title: 'Admin panel',
                          subtitle: 'Edit company secure info',
                          color: Colors.blue,
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              '/administratorPanel',
                            );
                          },
                        ),
                      ],
                      AdminCard(
                        icon: Icons.punch_clock,
                        title: 'Clock In / Out',
                        subtitle: 'Record Shift lengths',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.pushNamed(context, '/clockInOut');
                        },
                      ),
                      AdminCard(
                        icon: Icons.check_box,
                        title: 'ToDo List',
                        subtitle: 'create and check off toDoItems',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.pushNamed(context, '/toDoList');
                        },
                      ),
                      AdminCard(
                        icon: Icons.price_change,
                        title: 'Expense Tracker',
                        subtitle: 'log company or personal expenses',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.pushNamed(context, '/expenseTracker');
                        },
                      ),
                      AdminCard(
                        icon: Icons.image,
                        title: 'Company Images',
                        subtitle: 'images of jobs',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.pushNamed(context, '/constructionImages');
                        },
                      ),
                      AdminCard(
                        icon: Icons.contact_phone,
                        title: 'Contacts',
                        subtitle: 'Company Contacts',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.pushNamed(context, '/contacts');
                        },
                      ),
                      AdminCard(
                        icon: Icons.query_stats,
                        title: 'Work Stats',
                        subtitle: 'graphs + recent shifts',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.pushNamed(context, '/workStats');
                        },
                      ),
                    ],
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
