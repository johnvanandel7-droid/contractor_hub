import 'package:flutter/material.dart';

class GoHomeButton extends StatelessWidget {
  const GoHomeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.home),
      onPressed: () {
        Navigator.pushNamed(context, '/homePage');
      }
    );
  }
}