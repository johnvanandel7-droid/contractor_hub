import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';

final services = FirebaseServices.instance;

class ExpenseTracker extends StatefulWidget {
  const ExpenseTracker({super.key});

  @override
  State<ExpenseTracker> createState() => _ExpenseTrackerState();
}

class _ExpenseTrackerState extends State<ExpenseTracker> {
  String? selectedJobId;
  String? selectedCostCode;
  DateTime selectedDate = DateTime.now();
  final TextEditingController amountController = TextEditingController();
  List<DropdownMenuItem> costCodes = [
    DropdownMenuItem(child: Text('Kubota 75')),
    DropdownMenuItem(child: Text('terex')),
    DropdownMenuItem(child: Text('mini ex')),
    DropdownMenuItem(child: Text('jobsite')),
    DropdownMenuItem(child: Text('time and material')),
    DropdownMenuItem(child: Text('Kubota 75')),
    DropdownMenuItem(child: Text('Kubota 75')),
  ];

  late final Future<Stream<QuerySnapshot<Map<String, dynamic>>>?>
  _jobsStreamFuture;

  @override
  void initState() {
    super.initState();
    _jobsStreamFuture = services.getCompanyJobs();
  }

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: selectedDate,
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  Widget _buildJobDropdown() {
    return FutureBuilder<Stream<QuerySnapshot<Map<String, dynamic>>>?>(
      future: _jobsStreamFuture,
      builder: (context, futureSnapshot) {
        if (futureSnapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }

        final jobsStream = futureSnapshot.data;
        if (jobsStream == null) {
          return const Text('Could not load jobs');
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: jobsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Text('No jobs found');
            }

            return DropdownButton<String>(
              value: selectedJobId,
              icon: const Icon(Icons.arrow_downward),
              hint: const Text('Select a Job'),
              isExpanded: true,
              borderRadius: BorderRadius.all(Radius.circular(5)),
              items: docs.map((doc) {
                final jobName =
                    doc.data()['jobName'] as String? ?? 'Unnamed job';
                return DropdownMenuItem<String>(
                  value: doc.id,
                  child: Text(jobName),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => selectedJobId = value);
              },
            );
          },
        );
      },
    );
  }

  Widget costCodeDropdown() {
    return DropdownButton(value: selectedCostCode, icon: const Icon(Icons.arrow_downward), hint: const Text('select a cost code'),borderRadius: BorderRadius.all(Radius.circular(5)),items: , onChanged: onChanged)
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              '-Create PO-------------------',
              style: TextStyle(fontSize: 18),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white70,
                border: Border(),
                borderRadius: BorderRadius.all(Radius.circular(5)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('Job Name:'),
                      SizedBox(width: 4),
                      Expanded(child: _buildJobDropdown()),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(children: [Text('Cost Code:'), SizedBox(width: 4), costCodeDropdown(), SizedBox(width: 3), IconButton(onPressed: () {}, icon: Icon(Icons.add))]),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Text('Date:'),
                      SizedBox(width: 4),
                      TextButton(
                        onPressed: _pickDate,
                        child: Text(
                          '${selectedDate.month}/${selectedDate.day}/${selectedDate.year}',
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Amount (inc Tax)'),
                      SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: kInputDecoration,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
