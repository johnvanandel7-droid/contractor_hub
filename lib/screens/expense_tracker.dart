import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  String? _companyId;
  String? PONote;
  bool? isReimbursable = false;
  bool? isBillable = false;
  ImageSource? imageSource;
  final ImagePicker _picker = ImagePicker();
  XFile? pickedImage;

  // NOTE: give each item an explicit `value` or DropdownButton can't match
  // `selectedCostCode` back to an item, and dedupe the accidental repeats.
  final List<String> costCodes = const [
    'Kubota 75',
    'terex',
    'mini ex',
    'jobsite',
    'time and material',
  ];

  Stream<QuerySnapshot<Map<String, dynamic>>>? _jobsStream;
  bool _loadingJobs = true;

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
          : services.jobsForCompany(companyId);
      _loadingJobs = false;
    });
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
          print(snapshot.error);
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
            final jobName = doc.data()['name'] as String? ?? 'Unnamed job';
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
  }

  Widget costCodeDropdown() {
    return DropdownButton<String>(
      value: selectedCostCode,
      icon: const Icon(Icons.arrow_downward),
      hint: const Text('select a cost code'),
      borderRadius: BorderRadius.all(Radius.circular(5)),
      items: costCodes
          .map(
            (code) => DropdownMenuItem<String>(value: code, child: Text(code)),
          )
          .toList(),
      onChanged: (value) => setState(() {
        selectedCostCode = value;
      }),
    );
  }

  void getImages() async {
    try {
      final picked = await _picker.pickImage(
        source: imageSource!,
        imageQuality: 85,
      );
      setState(() {
        pickedImage = picked;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Faile to pick image')));
    }
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
                  Row(
                    children: [
                      Text('Cost Code:'),
                      SizedBox(width: 4),
                      costCodeDropdown(),
                      SizedBox(width: 3),
                      IconButton(onPressed: () {}, icon: Icon(Icons.add)),
                    ],
                  ),
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
                          decoration: kInputDecoration.copyWith(
                            hintText: '\$1000',
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Text('Notes:'),
                      SizedBox(width: 3),
                      TextField(
                        decoration: kInputDecoration.copyWith(
                          hintText: 'bought it too fix the skidsteer',
                        ),
                        onChanged: (value) {
                          setState(() {
                            PONote = value;
                          });
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Checkbox(
                        value: isReimbursable,
                        onChanged: (value) {
                          setState(() {
                            isReimbursable = value;
                          });
                        },
                      ),
                      SizedBox(width: 1),
                      Text('Reimbursable'),
                      SizedBox(width: 5),
                      Checkbox(
                        value: isBillable,
                        onChanged: (value) {
                          setState(() {
                            isBillable = value;
                          });
                        },
                      ),
                      SizedBox(width: 1),
                      Text('Billable'),
                    ],
                  ),
                  SizedBox(width: 10),
                  Row(
                    children: [
                      Spacer(flex: 2),
                      IconButton(
                        icon: Icon(Icons.camera_alt, size: 35),
                        onPressed: () {
                          setState(() {
                            imageSource = ImageSource.camera;
                          });
                          getImages();
                        },
                      ),
                      Spacer(flex: 1),
                      IconButton(
                        icon: Icon(Icons.image, size: 35),
                        onPressed: () {
                          setState(() {
                            imageSource = ImageSource.gallery;
                          });
                          getImages();
                        },
                      ),
                      Spacer(flex: 2),
                    ],
                  ),

                  ElevatedButton(
                    onPressed: () {
                      firebase.collection('POlogs').add({
                        'companyId': _companyId,
                        'createdBy': services.currentUid,
                        'costCode': selectedCostCode,
                        'job': selectedJobId,
                        'date': selectedDate,
                        'note': PONote,
                        'images': pickedImage?.path,
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      fixedSize: Size(100, 40),
                    ),
                    child: Text('Add'),
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
