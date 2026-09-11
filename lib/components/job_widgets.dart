import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/constants.dart';
import 'package:flutter/material.dart';

final _firestore = FirebaseFirestore.instance;

/// A single job "card": shows the job name, with buttons to edit the job,
/// add a photo to it, and select it as the active job.
class JobPhotoPicker extends StatefulWidget {
  final String jobId;
  final String jobName;
  final Color? color;
  final VoidCallback onSelection;
  final VoidCallback onTap;

  const JobPhotoPicker({
    super.key,
    required this.jobId,
    required this.jobName,
    required this.color,
    required this.onSelection,
    required this.onTap,
  });

  @override
  State<JobPhotoPicker> createState() => _JobPhotoPickerState();
}

class _JobPhotoPickerState extends State<JobPhotoPicker> {
  Future<void> _editJob() async {
    final TextEditingController editController = TextEditingController(
      text: widget.jobName,
    );

    await showBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Edit Job', style: TextStyle(fontSize: 20)),
                const SizedBox(height: 15),
                TextField(
                  controller: editController,
                  decoration: kInputDecoration.copyWith(hintText: 'New Name'),
                ),
                const SizedBox(height: 15),
                MaterialButton(
                  color: Colors.blue,
                  onPressed: () async {
                    final newName = editController.text.trim();
                    if (newName.isEmpty) return;

                    try {
                      await _firestore
                          .collection('jobs')
                          .doc(widget.jobId)
                          .update({'jobName': newName});
                    } catch (e) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        SnackBar(content: Text('Failed to update job: $e')),
                      );
                      return;
                    }

                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: kboxDecoration.copyWith(color: widget.color),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Text(widget.jobName, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  IconButton(onPressed: _editJob, icon: const Icon(Icons.edit)),
                  const Spacer(),
                  IconButton(
                    onPressed: widget.onTap,
                    icon: const Icon(Icons.add),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: widget.onSelection,
                    icon: const Icon(Icons.arrow_downward),
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

/// Streams the jobs belonging to [companyId] and renders one
/// JobPhotoPicker card per job, laid out in a horizontally scrollable row.
/// Queries Firestore directly so this widget is self-contained and doesn't
/// depend on any other screen file being imported for it to compile.
class JobsAndImagesDisplay extends StatelessWidget {
  final String companyId;
  final String? selectedJobId;
  final ValueChanged<String> onJobSelected;
  final ValueChanged<String> onAddImage;

  const JobsAndImagesDisplay({
    super.key,
    required this.companyId,
    required this.selectedJobId,
    required this.onJobSelected,
    required this.onAddImage,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('jobs')
          .where('companyId', isEqualTo: companyId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('No jobs yet — tap "Add Job" to create one'),
          );
        }

        final docs = snapshot.data!.docs;
        final List<Widget> jobPhotos = [];

        for (final doc in docs) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            final jobName = data['jobName'] as String? ?? 'Unnamed job';
            final jobId = doc.id;

            jobPhotos.add(
              JobPhotoPicker(
                jobId: jobId,
                jobName: jobName,
                color: selectedJobId == jobId ? Colors.blue : Colors.blue[700],
                onSelection: () => onJobSelected(jobId),
                onTap: () => onAddImage(jobId),
              ),
            );
          } catch (e) {
            jobPhotos.add(
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('error parsing job: $e'),
              ),
            );
          }
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: jobPhotos),
        );
      },
    );
  }
}
