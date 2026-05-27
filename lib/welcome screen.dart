import 'package:contractor_hub/reusable_button.dart';
import 'package:flutter/material.dart';

class LoginOrCreateAccount extends StatelessWidget {
  const LoginOrCreateAccount({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ReusableButton(
                buttonText: 'Login', 
                onPress: () => Navigator.pushNamed(context, '/loginPage'),
                buttonHeight: 30, 
                buttonWidth: double.infinity, 
                buttonColor: Colors.white,
                buttonPadding: 20,
              ),
            ),
            Expanded(
              child: ReusableButton(
                buttonText: 'Create New Account', 
                onPress: () => Navigator.pushNamed(context, '/createNewAccount'),
                buttonHeight: 30, 
                buttonWidth: double.infinity, 
                buttonColor: Colors.white,
                buttonPadding: 20,
              ),
            )
          ],
        ),
      )
    );
  }
}