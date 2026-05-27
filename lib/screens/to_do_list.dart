import 'package:contractor_hub/components/go_home.dart';
import 'package:flutter/material.dart';

class ToDoList extends StatelessWidget {
  const ToDoList({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: [GoHomeButton()]),
      backgroundColor: Colors.blue[200],
    );
  }
}
