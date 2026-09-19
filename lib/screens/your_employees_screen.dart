import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/time_ago.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';

final _services = FirebaseServices.instance;

class YourEmployeesScreen extends StatelessWidget {
  const YourEmployeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('Your Employees', style: TextStyle(fontSize: 20)),
          SizedBox(height: 20),
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
            final data = doc.data() as Map<String, dynamic>;
            final name = data['name'] as String? ?? 'Unknown';
            final hiredAt = data['createdAt'] as Timestamp;

            employees.add(EmployeeInfoContainer(name: name, hiredAt: hiredAt));
          } catch (e) {
            return Center(child: Text('Error parsing employees'));
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
  final Timestamp hiredAt;

  const EmployeeInfoContainer({
    super.key,
    required this.name,
    required this.hiredAt,
  });

  @override
  State<EmployeeInfoContainer> createState() => _EmployeeInfoContainerState();
}

class _EmployeeInfoContainerState extends State<EmployeeInfoContainer> {
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
                  Text(formatTimeAgo(widget.hiredAt)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
