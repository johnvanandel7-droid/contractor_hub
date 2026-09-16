import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/components/reusable_button.dart';
import 'package:flutter/material.dart';

class AdministratorPanel extends StatelessWidget {
  const AdministratorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(),
      body: Column(
        children: [
          SizedBox(height: 10),
          Text('Administrator panel', style: TextStyle(fontSize: 20)),
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
            buttonText: 'Jobs',
            onPress: () {
              Navigator.pushNamed(context, '/yourJobs');
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
              Navigator.pushNamed(context, '/yourFiles');
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
