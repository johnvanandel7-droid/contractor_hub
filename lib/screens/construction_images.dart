import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

final firestore = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
final services = FirebaseServices.instance;

class ConstructionImages extends StatefulWidget {
  const ConstructionImages({super.key});

  @override
  State<ConstructionImages> createState() => _ConstructionImagesState();
}

class _ConstructionImagesState extends State<ConstructionImages> {
  // Currently selected job's Firestore doc id (jobs are now real Firestore
  // documents, so this needs to be a String, not the old hardcoded int).
  String? selectedJobId;

  final ImagePicker _picker = ImagePicker();
  List<XFile> images = [];
  final TextEditingController newJobNameController = TextEditingController();

  String? companyId;
  String? companyPaymentPlan;
  int maxCompanyImages = 0;
  bool loadingCompanyInfo = true;

  @override
  void initState() {
    super.initState();
    getCompanyInfo();
  }

  @override
  void dispose() {
    newJobNameController.dispose();
    super.dispose();
  }

  Future<void> getCompanyInfo() async {
    setState(() {
      loadingCompanyInfo = true;
    });

    try {
      final uid = auth.currentUser?.uid;
      if (uid == null) {
        setState(() {
          companyId = null;
          loadingCompanyInfo = false;
        });
        return;
      }

      final userDoc = await firestore.collection('users').doc(uid).get();
      final fetchedCompanyId = userDoc.data()?['companyId'] as String?;

      if (fetchedCompanyId == null) {
        setState(() {
          companyId = null;
          loadingCompanyInfo = false;
        });
        return;
      }

      final companyDoc = await firestore
          .collection('companies')
          .doc(fetchedCompanyId)
          .get();

      final plan =
          companyDoc.data()?['companyPaymentPlan'] as String? ?? 'small';

      if (!mounted) return;
      setState(() {
        companyId = fetchedCompanyId;
        companyPaymentPlan = plan;
        maxCompanyImages = _maxImagesForPlan(plan);
        loadingCompanyInfo = false;
      });
    } catch (e) {
      debugPrint('error loading company info: $e');
      if (!mounted) return;
      setState(() {
        companyId = null;
        loadingCompanyInfo = false;
      });
    }
  }

  int _maxImagesForPlan(String plan) {
    switch (plan) {
      case 'medium':
        return 2000;
      case 'large':
        return 1000000000;
      case 'small':
      default:
        return 250;
    }
  }

  Future<int> _currentCompanyImageCount() async {
    if (companyId == null) return 0;
    final countSnapshot = await firestore
        .collection('jobImages')
        .where('companyId', isEqualTo: companyId)
        .count()
        .get();
    return countSnapshot.count ?? 0;
  }

  // Creates a new job document under the 'jobs' collection for this
  // company. Kept separate from 'jobImages' (which stores individual
  // uploaded photos) to avoid mixing the two kinds of documents together.
  Future<void> addNewJob() async {
    if (companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine your company')),
      );
      return;
    }

    newJobNameController.clear();

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
                const Text('Add Job', style: TextStyle(fontSize: 20)),
                const SizedBox(height: 15),
                TextField(
                  decoration: kInputDecoration.copyWith(hintText: 'Name'),
                  controller: newJobNameController,
                ),
                const SizedBox(height: 15),
                MaterialButton(
                  color: Colors.blue,
                  onPressed: () async {
                    final jobName = newJobNameController.text.trim();
                    if (jobName.isEmpty) return;

                    try {
                      await firestore.collection('jobs').add({
                        'jobName': jobName,
                        'companyId': companyId,
                        'createdAt': FieldValue.serverTimestamp(),
                        'jobImages': [],
                      });
                    } catch (e) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        SnackBar(content: Text('Failed to create job: $e')),
                      );
                      return;
                    }

                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  child: const Text('Save Job'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> addImages({required String jobId}) async {
    if (loadingCompanyInfo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still loading company info, try again in a moment'),
        ),
      );
      return;
    }

    if (companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not determine your company, please try again later',
          ),
        ),
      );
      return;
    }

    // check firestore to see if theres room for more images
    final currentCompanyImageCount = await _currentCompanyImageCount();
    if (currentCompanyImageCount >= maxCompanyImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your company has reached its image limit ($maxCompanyImages) for the $companyPaymentPlan plan. Upgrade to add more.',
          ),
        ),
      );
      return;
    }

    // show a nice dialog to let user choose camera or gallery
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('choose photo adding method'),
        content: Row(
          children: [
            MaterialButton(
              onPressed: () {
                Navigator.pop(context, ImageSource.gallery);
              },
              child: Text('gallery'),
            ),
            MaterialButton(
              onPressed: () {
                Navigator.pop(context, ImageSource.camera);
              },
              child: Text('camera'),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );

    // If user cancelled the dialog
    if (source == null) return;

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;

      setState(() {
        images.add(picked);
      });

      await firestore.collection('jobImages').add({
        'companyId': companyId,
        'jobId': jobId,
        'imagePath': picked.path,
        'uploadedAt': FieldValue.serverTimestamp(),
        'uploadedBy': auth.currentUser?.uid,
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to pick image')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text(
                'Construction Images',
                style: TextStyle(fontSize: 20),
              ),
            ),
            if (loadingCompanyInfo)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (companyId == null)
              const Expanded(
                child: Center(child: Text('Could not determine your company')),
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: GestureDetector(
                        onTap: addNewJob,
                        child: Container(
                          decoration: kboxDecoration,
                          padding: const EdgeInsets.all(8),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: 10),
                              Text('Add Job', style: TextStyle(fontSize: 15)),
                              Icon(Icons.add),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: JobsAndImagesDisplay(
                        companyId: companyId!,
                        selectedJobId: selectedJobId,
                        onJobSelected: (id) =>
                            setState(() => selectedJobId = id),
                        onAddImage: (id) => addImages(jobId: id),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
                      await firestore
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

// Streams the jobs belonging to [companyId] and renders one JobPhotoPicker
// card per job. Selecting a job or tapping its "add" icon calls back up to
// the parent so it can update selection state / trigger the image picker
// with the correct jobId.
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
      stream: services.streamJobImages(companyId),
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
