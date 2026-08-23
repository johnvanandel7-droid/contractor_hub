import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/go_home.dart';
import 'package:contractor_hub/components/time_ago.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

final auth = FirebaseAuth.instance;
final firebase = FirebaseFirestore.instance;
final services = FirebaseServices.instance;
int toDoListLength = 0;

class ToDoList extends StatefulWidget {
  const ToDoList({super.key});

  @override
  State<ToDoList> createState() => _ToDoListState();
}

class _ToDoListState extends State<ToDoList> {
  TextEditingController newTaskController = TextEditingController();
  DateTime? _completionDate;
  String? _companyName;

  String get _currentUserUid => auth.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  Future<void> _loadCompany() async {
    final user = await services.getUser(_currentUserUid);
    if (mounted) {
      setState(() {
        _companyName = user?['companyName'] as String?;
      });
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _completionDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
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
              MaterialButton(
                onPressed: () => _pickDate(context),
                child: Container(
                  decoration: BoxDecoration(color: Colors.grey),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Choose Completion date'),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (newTaskController.text.trim().isEmpty ||
                      _companyName == null) {
                    return;
                  }
                  Navigator.pop(context);
                  await firebase.collection('ToDoItems').add({
                    'message': newTaskController.text,
                    'createdAt': DateTime.now,
                    'completionDate': _completionDate,
                    'createdBy': _currentUserUid,
                    'companyName': _companyName,
                  });
                  newTaskController.clear();
                  _completionDate = null;
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
      body: _companyName == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Text('To Do List ($toDoListLength)'),
                Expanded(child: ToDoListItems(companyName: _companyName!)),
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

class ToDoListItems extends StatelessWidget {
  final String companyName;

  const ToDoListItems({super.key, required this.companyName});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firebase
          .collection('ToDoItems')
          .where('companyName', isEqualTo: companyName)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No orders yet'));
        }
        final docs = snapshot.data!.docs;
        final tiles = <ToDoTile>[];

        for (final doc in docs) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            final toDoMessage = data['message'] as String;
            final completionDate = data['completionDate'] as Timestamp;
            final createdAt = data['createdAt'] as Timestamp;
            final createdBy = data['createdBy'] as String;

            toDoListLength++;
            tiles.add(
              ToDoTile(
                completionDate: completionDate,
                toDoMessage: toDoMessage,
                createdAt: createdAt,
                createdBy: createdBy,
              ),
            );
          } catch (e) {
            continue;
          }
        }

        return ListView(padding: EdgeInsets.all(8.0), children: tiles);
      },
    );
  }
}

class ToDoTile extends StatelessWidget {
  final String toDoMessage;
  final Timestamp completionDate;
  final Timestamp createdAt;
  final String createdBy;

  const ToDoTile({
    super.key,
    required this.completionDate,
    required this.toDoMessage,
    required this.createdAt,
    required this.createdBy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blueGrey,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                '$toDoMessage - completion date ${formatTimeAgo(completionDate)}',
              ),
            ),
            Text(
              'created at: ${formatTimeAgo(createdAt)} -- created by $createdBy',
            ),
          ],
        ),
      ),
    );
  }
}
