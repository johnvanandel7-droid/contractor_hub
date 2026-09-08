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
  int selectedJob = 1;
  List<JobPhotoPicker> jobs = [];
  final ImagePicker _picker = ImagePicker();
  List<XFile> images = [];
  TextEditingController newJobNameController = TextEditingController();

  String? companyId;
  String? companyPaymentPlan;
  int maxCompanyImages = 0;
  bool loadingCompanyInfo = true;

  @override
  void initState() {
    super.initState();
    getCompanyInfo();
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

  Future<void> addimages() async {
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

    // check firestore  to see if theres room for more images
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
        'jobId': selectedJob,
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

  Future<void> addNewJob() async {
    await showBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Column(
            children: [
              Text('Add Job', style: TextStyle(fontSize: 20)),
              SizedBox(height: 15),
              TextField(
                decoration: kInputDecoration.copyWith(hintText: 'Name'),
                controller: newJobNameController,
              ),
              SizedBox(height: 15),
              MaterialButton(
                onPressed: () async {
                  await firestore.collection('JobImages').doc().add({
                    'name': newJobNameController,
                    'companyId': companyId,
                    'createdAt': Timestamp.now(),
                    'jobImages': [],
                  });
                  Navigator.pop(context);
                },
                child: Text('Save Job'),
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
      body: Column(
        children: [
          Text('Construction Images', style: TextStyle(fontSize: 20)),
          Row(
            children: [
              GestureDetector(
                onTap: () {},
                child: Container(
                  decoration: kboxDecoration,
                  child: Column(
                    children: [
                      SizedBox(height: 10),
                      Text('Add Job', style: TextStyle(fontSize: 15)),
                      Icon(Icons.add),
                    ],
                  ),
                ),
              ),
              ...jobs,
            ],
          ),
        ],
      ),
    );
  }
}

class JobPhotoPicker extends StatefulWidget {
  final String jobName;
  final Color? color;
  final VoidCallback onSelection;
  final VoidCallback onTap;

  const JobPhotoPicker({
    super.key,
    required this.jobName,
    required this.color,
    required this.onSelection,
    required this.onTap,
  });

  @override
  State<JobPhotoPicker> createState() => _JobPhotoPickerState();
}

class _JobPhotoPickerState extends State<JobPhotoPicker> {
  Future<void> _editJob(String jobId) async {
    await showBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Column(
            children: [
              Text('Edit Job', style: TextStyle(fontSize: 20)),
              SizedBox(height: 15),
              TextField(
                decoration: kInputDecoration.copyWith(hintText: 'New Name'),
              ),
            ],
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
              Text(widget.jobName, style: TextStyle(fontSize: 20)),
              SizedBox(height: 8),
              Row(
                children: [
                  Spacer(),
                  IconButton(
                    onPressed: () {
                      _editJob();
                    },
                    icon: Icon(Icons.edit),
                  ),
                  Spacer(),
                  IconButton(onPressed: widget.onTap, icon: Icon(Icons.add)),
                  Spacer(),
                  IconButton(
                    onPressed: widget.onSelection,
                    icon: Icon(Icons.arrow_downward),
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

class JobsAndImagesDisplay extends StatelessWidget {
  final String companyId;

  const JobsAndImagesDisplay({super.key, required this.companyId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: services.streamJobImages(companyId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No Jobs yet'));
        }

        final docs = snapshot.data!.docs;
        final List<JobPhotoPicker> jobPhotos = [];

        for (final doc in docs) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            final jobName = data['jobName'] as String;

            jobPhotos.add(
              JobPhotoPicker(
                jobName: jobName,
                color: Colors.blueGrey,
                onSelection: ,
                onTap: onTap,
              ),
            );
          } catch (e) {
            return Center(child: Text('error parsing job $e'));
          }
        }
      },
    );
  }
}
