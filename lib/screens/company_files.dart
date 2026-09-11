import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/job_widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

final _firestore = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

class CompanyFiles extends StatefulWidget {
  const CompanyFiles({super.key});

  @override
  State<CompanyFiles> createState() => _CompanyFilesState();
}

class _CompanyFilesState extends State<CompanyFiles> {
  bool loadingCompanyInfo = false;
  String? companyId;
  String? selectedJobId;
  String? companyPaymentPlan;
  int maxCompanyImages = 0;

  final ImagePicker _picker = ImagePicker();

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
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        setState(() {
          companyId = null;
          loadingCompanyInfo = false;
        });
        return;
      }

      final userDoc = await _firestore.collection('users').doc(uid).get();
      final fetchedCompanyId = userDoc.data()?['companyId'] as String?;

      if (fetchedCompanyId == null) {
        setState(() {
          companyId = null;
          loadingCompanyInfo = false;
        });
        return;
      }

      final companyDoc = await _firestore
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

  // Same per-plan quota used on the construction images screen, so limits
  // stay consistent wherever images get added from.
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
    final countSnapshot = await _firestore
        .collection('jobImages')
        .where('companyId', isEqualTo: companyId)
        .count()
        .get();
    return countSnapshot.count ?? 0;
  }

  Future<void> addImages({required String jobId}) async {
    if (companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine your company')),
      );
      return;
    }

    final currentCount = await _currentCompanyImageCount();
    if (currentCount >= maxCompanyImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your company has reached its image limit ($maxCompanyImages) for the $companyPaymentPlan plan. Upgrade to add more.',
          ),
        ),
      );
      return;
    }

    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('choose photo adding method'),
        content: Row(
          children: [
            MaterialButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, ImageSource.gallery),
              child: const Text('gallery'),
            ),
            MaterialButton(
              onPressed: () => Navigator.pop(dialogContext, ImageSource.camera),
              child: const Text('camera'),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );

    if (source == null) return;

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;

      await _firestore.collection('jobImages').add({
        'companyId': companyId,
        'jobId': jobId,
        'imagePath': picked.path,
        'uploadedAt': FieldValue.serverTimestamp(),
        'uploadedBy': _auth.currentUser?.uid,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to pick image')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loadingCompanyInfo) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (companyId == null) {
      return const Scaffold(
        body: Center(child: Text('Could not determine your company')),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 20),
          const Text('Company Files', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 20),
          Expanded(
            child: JobsAndImagesDisplay(
              companyId: companyId!,
              selectedJobId: selectedJobId,
              onJobSelected: (value) {
                setState(() => selectedJobId = value);
              },
              onAddImage: (jobId) => addImages(jobId: jobId),
            ),
          ),
          MaterialButton(
            onPressed: selectedJobId == null
                ? null
                : () => addImages(jobId: selectedJobId!),
            child: const Text('Add Files'),
          ),
        ],
      ),
    );
  }
}
