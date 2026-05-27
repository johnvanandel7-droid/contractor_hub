import 'package:contractor_hub/go_home.dart';
import 'package:flutter/material.dart';

class ClockInOut extends StatelessWidget {
  const ClockInOut({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          GoHomeButton(),
        ],
      ),
      backgroundColor: Colors.pink,
      body: Text('hi'),
    );
  }
}