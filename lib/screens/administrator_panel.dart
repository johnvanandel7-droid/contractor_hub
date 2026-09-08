import 'package:contractor_hub/components/reusable_button.dart';
import 'package:flutter/material.dart';

class AdministratorPanel extends StatelessWidget {
  const AdministratorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('Administrator panel'),
          SizedBox(height: 10),
          ReusableButton(
            buttonText: 'Employees',
            onPress: () {
              Navigator.pushNamed(context, '/yourEmployees');
            },
            buttonHeight: 50,
            buttonWidth: double.infinity,
            buttonColor: Colors.blue,
            buttonPadding: 10,
          ),
          SizedBox(height: 10),
          ReusableButton(
            buttonText: 'Files',
            onPress: () {
              Navigator.pushNamed(context, 'yourEmployees');
            },
            buttonHeight: 50,
            buttonWidth: double.infinity,
            buttonColor: Colors.blue,
            buttonPadding: 10,
          ),
        ],
      ),
    );
  }
}
