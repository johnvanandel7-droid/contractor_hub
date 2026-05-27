import 'package:contractor_hub/constants.dart';
import 'package:flutter/material.dart';
import '../components/reusable_button.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        shadowColor: Colors.black,
        elevation: 10,
        title: Text('Contractor Hub', style: kLargeTextSize),
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ReusableButton(
                buttonText: 'Clock In / Out',
                onPress: () {
                  Navigator.pushNamed(context, '/clockInOut');
                },
                buttonHeight: 20,
                buttonWidth: double.infinity,
                buttonColor: Colors.purple,
                buttonPadding: 8,
              ),
            ),
            Expanded(
              child: ReusableButton(
                buttonText: 'ToDo List',
                onPress: () {
                  Navigator.pushNamed(context, '/toDoList');
                },
                buttonHeight: 20,
                buttonWidth: double.infinity,
                buttonColor: Colors.black87,
                buttonPadding: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
