import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ConstructionImages extends StatefulWidget {
  const ConstructionImages({super.key});

  @override
  State<ConstructionImages> createState() => _ConstructionImagesState();
}

class _ConstructionImagesState extends State<ConstructionImages> {
  final services = FirebaseServices.instance;
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  bool _loadingCompanyInfo = true;
  String? _companyId;
  String? _companyPaymentPlan;
  int _maxCompanyImages = 0;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _jobsStream;
  String? selectedJobId;

  @override
  void initState() {
    super.initState();
    _loadCompanyInfo();
  }

  Future<void> _loadCompanyInfo() async {
    setState(() => _loadingCompanyInfo = true);

    try {
      final uid = auth.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _companyId = null;
          _loadingCompanyInfo = false;
        });
        return;
      }

      final userDoc = await firestore.collection('users').doc(uid).get();
      final fetchedCompanyId = userDoc.data()?['companyId'] as String?;

      if (fetchedCompanyId == null) {
        setState(() {
          _companyId = null;
          _loadingCompanyInfo = false;
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
        _companyId = fetchedCompanyId;
        _companyPaymentPlan = plan;
        _maxCompanyImages = _maxImagesForPlan(plan);
        _jobsStream = services.jobsForCompany(fetchedCompanyId);
        _loadingCompanyInfo = false;
      });
    } catch (e) {
      debugPrint('error loading company info: $e');
      if (!mounted) return;
      setState(() {
        _companyId = null;
        _loadingCompanyInfo = false;
      });
    }
  }

  // Same per-plan quota used on the company files screen, so limits stay
  // consistent wherever images get added from.
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
    if (_companyId == null) return 0;
    final countSnapshot = await firestore
        .collection('jobImages')
        .where('companyId', isEqualTo: _companyId)
        .count()
        .get();
    return countSnapshot.count ?? 0;
  }

  Future<void> _addImages(String jobId) async {
    if (_companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine your company')),
      );
      return;
    }

    final currentCount = await _currentCompanyImageCount();
    if (currentCount >= _maxCompanyImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your company has reached its image limit ($_maxCompanyImages) for '
            'the $_companyPaymentPlan plan. Upgrade to add more.',
          ),
        ),
      );
      return;
    }

    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add a photo'),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogContext, ImageSource.gallery),
              icon: const Icon(Icons.image),
              label: const Text('Gallery'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Camera'),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;

      await firestore.collection('jobImages').add({
        'companyId': _companyId,
        'jobId': jobId,
        'imagePath': picked.path,
        'uploadedAt': FieldValue.serverTimestamp(),
        'uploadedBy': auth.currentUser?.uid,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add image: $e')));
    }
  }

  Future<void> _deleteImage(String imageId) async {
    try {
      await firestore.collection('jobImages').doc(imageId).delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete image: $e')));
    }
  }

  Future<void> _renameJob(String jobId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename job'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: kInputDecoration.copyWith(hintText: 'Job name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      try {
        await firestore.collection('jobs').doc(jobId).update({'name': newName});
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to rename job: $e')));
      }
    }
  }

  Widget _buildJobPickerRow() {
    final jobsStream = _jobsStream;
    if (jobsStream == null) {
      return const Center(child: Text('Could not load jobs'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: jobsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('No jobs yet — add one from the Jobs screen'),
          );
        }

        // A plain horizontal ListView, not a Row inside a
        // SingleChildScrollView: each item gets a fixed width from the
        // SizedBox below, so nothing downstream ever hits an unbounded
        // width constraint.
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final jobName = doc.data()['name'] as String? ?? 'Unnamed job';
            final isSelected = selectedJobId == doc.id;

            return SizedBox(
              width: 150,
              child: _JobCard(
                jobName: jobName,
                isSelected: isSelected,
                onTap: () => setState(() => selectedJobId = doc.id),
                onAddPhoto: () => _addImages(doc.id),
                onRename: () => _renameJob(doc.id, jobName),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildImageGrid() {
    final jobId = selectedJobId;
    if (jobId == null) {
      return Center(
        child: Text(
          'Select a job above to see and add its photos',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('jobImages')
          .where('companyId', isEqualTo: _companyId)
          .where('jobId', isEqualTo: jobId)
          // NOTE: this equality-filter + orderBy combination needs a
          // composite index. The first time this query runs, Flutter's
          // console output will include a link to create it automatically —
          // click that link once and it'll work from then on.
          .orderBy('uploadedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          print(snapshot.error);
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 8),
                Text(
                  'No photos for this job yet',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final path = data['imagePath'] as String? ?? '';
            final uploadedBy = data['uploadedBy'] as String?;
            final canDelete =
                uploadedBy != null && uploadedBy == auth.currentUser?.uid;

            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // NOTE: imagePath is the local device path of whoever
                  // uploaded it, so it only renders on that same device.
                  // Wire up Firebase Storage (upload the file, store the
                  // download URL) for photos that need to show up for
                  // everyone on every device.
                  Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey[200],
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
                  if (canDelete)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => _deleteImage(doc.id),
                        child: const CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.black54,
                          child: Icon(
                            Icons.close,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(),
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: _loadingCompanyInfo
            ? const Center(child: CircularProgressIndicator())
            : _companyId == null
            ? const Center(child: Text('Could not determine your company'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Construction Images',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 140, child: _buildJobPickerRow()),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: const Divider(height: 1),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _buildImageGrid(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final String jobName;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onAddPhoto;
  final VoidCallback onRename;

  const _JobCard({
    required this.jobName,
    required this.isSelected,
    required this.onTap,
    required this.onAddPhoto,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.blue[700],
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: Colors.blue[900]!, width: 2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              jobName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: onRename,
                  icon: const Icon(Icons.edit, color: Colors.white, size: 18),
                  tooltip: 'Rename',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  onPressed: onAddPhoto,
                  icon: const Icon(
                    Icons.add_a_photo,
                    color: Colors.white,
                    size: 18,
                  ),
                  tooltip: 'Add photo',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
