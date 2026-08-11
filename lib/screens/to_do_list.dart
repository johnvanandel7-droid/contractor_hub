import 'package:contractor_hub/components/go_home.dart';
import 'package:flutter/material.dart';

class ToDoList extends StatefulWidget {
  const ToDoList({super.key});

  @override
  State<ToDoList> createState() => _ToDoListState();
}

class _ToDoListState extends State<ToDoList> {
  List toDoItems = [];

  Future<void> _openNewTask() async {
    await showBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Column(
            children: [Text('New Task'), SizedBox(height: 20), TextField()],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: [GoHomeButton()]),
      backgroundColor: Colors.blue[200],
      body: Column(
        children: [
          Text('To Do List (${toDoItems.length})'),
          ElevatedButton(
            onPressed: () {
              _openNewTask();
            },
            child: Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
