import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';

final services = FirebaseServices.instance;

class MileageTracker extends StatefulWidget {
  const MileageTracker({super.key});

  @override
  State<MileageTracker> createState() => _MileageTrackerState();
}

class _MileageTrackerState extends State<MileageTracker> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _jobsStream;
  bool _loadingJobs = true;
  String? _companyId;
  String? selectedJobId;

  @override
  void initState() {
    super.initState();
    _loadJobsStream();
  }

  Future<void> _loadJobsStream() async {
    final userId = services.currentUid;
    if (userId == null) {
      setState(() => _loadingJobs = false);
      return;
    }

    final companyId = await services.getUsersCompanyId(userId);
    if (!mounted) return;

    setState(() {
      _companyId = companyId;
      _jobsStream = companyId == null
          ? null
          : services.jobsForCompany(_companyId!);
      _loadingJobs = false;
    });
  }

  Widget _buildJobDropdown() {
    if (_loadingJobs) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final jobsStream = _jobsStream;
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

        return InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Job',
            border: OutlineInputBorder(),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedJobId,
              isExpanded: true,
              hint: const Text('Select a job'),
              items: docs.map((doc) {
                final jobName = doc.data()['name'] as String? ?? 'Unnamed job';
                return DropdownMenuItem<String>(
                  value: doc.id,
                  child: Text(jobName),
                );
              }).toList(),
              onChanged: (value) => setState(() => selectedJobId = value),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text('- Create Travel Log ---', style: TextStyle(fontSize: 20)),
            SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: kboxDecoration,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [Text('JobName'), _buildJobDropdown()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
