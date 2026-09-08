import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/reusable_button.dart';

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
      return Center(child: Text('User isnt logged in'));
    }
    return Scaffold(
      appBar: AppBar(
        shadowColor: Colors.black,
        elevation: 10,
        title: Text('Contractor Hub', style: kLargeTextSize),
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: services.getUser(currentUserUid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data == null) {
              return const Center(child: Text('Could not load your account'));
            }

            final bool isEmployee =
                snapshot.data!['isEmployee'] as bool? ?? true;
            return SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isEmployee == false) ...[
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
