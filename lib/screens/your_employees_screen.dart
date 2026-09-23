import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/components/time_ago.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/screens/to_do_list.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';

final _services = FirebaseServices.instance;

class YourEmployeesScreen extends StatelessWidget {
  const YourEmployeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(),
      body: Column(
        children: [
          Text('Your Employees', style: TextStyle(fontSize: 20)),
          SizedBox(height: 20),
          Expanded(child: DisplayEmployeeList()),
        ],
      ),
    );
  }
}

class DisplayEmployeeList extends StatelessWidget {
  const DisplayEmployeeList({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _services.streamYourEmployees(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No employees yet'));
        }

        final docs = snapshot.data!.docs;
        final List<EmployeeInfoContainer> employees = [];

        for (final doc in docs) {
          try {
            final data = doc.data();
            final name = data['name'] as String? ?? 'Unknown';
            final hiredAt = data['createdAt'] as Timestamp?;

            employees.add(
              EmployeeInfoContainer(name: name, hiredAt: hiredAt, uid: doc.id),
            );
          } catch (e) {
            debugPrint('error parsing employees :::::$e');
            continue;
          }
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: employees,
        );
      },
    );
  }
}

class EmployeeInfoContainer extends StatefulWidget {
  final String name;
  Timestamp? hiredAt;
  final String uid;

  EmployeeInfoContainer({
    super.key,
    required this.name,
    this.hiredAt,
    required this.uid,
  });

  @override
  State<EmployeeInfoContainer> createState() => _EmployeeInfoContainerState();
}

class _EmployeeInfoContainerState extends State<EmployeeInfoContainer> {
  _editEmployee() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${widget.name}\'s account'),
        constraints: BoxConstraints(maxHeight: 400),
        content: Column(
          children: [
            Text('edit name'),
            TextField(
              decoration: kInputDecoration.copyWith(hintText: 'New Name'),
              controller: controller,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              try {
                await _services.updateEmployeeName(widget.uid, newName);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Failed to update name: $e')),
                  );
                }
              }
            },
            child: const Text('save'),
          ),
        ],
      ),
    );
  }

  _confirmDelete() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('confirm delete of ${widget.name}'),
        constraints: BoxConstraints(maxHeight: 400),
        content: Column(
          children: [
            Text('Delete ${widget.name}'),
            Row(
              children: [
                Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text('cancel'),
                ),
                Spacer(),
                TextButton(
                  onPressed: () async {
                    try {
                      await _services.deleteEmployee(widget.uid);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to delete: $e')),
                        );
                      }
                    }
                  },
                  child: Text('delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(10),
      child: Container(
        decoration: kboxDecoration,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Row(
                children: [
                  Text(widget.name),
                  SizedBox(width: 15),
                  Text(
                    widget.hiredAt == null
                        ? 'Unknown'
                        : formatTimeAgo(widget.hiredAt),
                  ),
                ],
              ),
              Row(
                children: [
                  Spacer(),
                  IconButton(onPressed: _editEmployee, icon: Icon(Icons.edit)),
                  Spacer(),
                  IconButton(
                    onPressed: () {
                      _confirmDelete();
                    },
                    icon: Icon(Icons.delete),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
