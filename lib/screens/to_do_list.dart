import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/go_home.dart';
import 'package:contractor_hub/constants.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

final auth = FirebaseAuth.instance;
final firebase = FirebaseFirestore.instance;

class ToDoList extends StatefulWidget {
  const ToDoList({super.key});

  @override
  State<ToDoList> createState() => _ToDoListState();
}

class _ToDoListState extends State<ToDoList> {
  TextEditingController newTaskController = TextEditingController();
  DateTime? _completionDate;

  final String currentUserUid = auth.currentUser!.uid;

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(context: context, initialDate: _completionDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (pickedDate != null && pickedDate != _completionDate) {
      setState(() {
        _completionDate = pickedDate;
      });
    }
  }

  Future<void> _openNewTask() async {
    await showBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Column(
            children: [
              Text('New Task'),
              SizedBox(height: 20),
              TextField(
                controller: newTaskController,
                decoration: kInputDecoration.copyWith(
                  hintText: 'take out garbage',
                ),
              ),
              SizedBox(height: 10),
              Text('Completion date'),
              MaterialButton(onPressed: () => _pickDate(context), child: Container(decoration: BoxDecoration(color: Colors.grey,), child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('Choose Completion date'),
              ),)),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await firebase.collection('ToDoItems').add({
                    'message': newTaskController.text,
                    'createdAt': DateTime.now,
                    'completionDate': 
                  });
                },
                child: Text('Save'),
              ),
            ],
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
