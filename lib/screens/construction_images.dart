import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/constants.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

final firestore = FirebaseFirestore.instance;

class ConstructionImages extends StatefulWidget {
  const ConstructionImages({super.key});

  @override
  State<ConstructionImages> createState() => _ConstructionImagesState();
}

class _ConstructionImagesState extends State<ConstructionImages> {
  int selectedJob = 1;
  List<JobPhotoPicker> jobs = [];
  final ImagePicker _picker = ImagePicker();
  List<XFIle> images = [];

  Future<void> addimages() async {
    if (images.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You have surpassed the max ammount of construction images available',
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

      firestore.collection('jobImages').add(picked);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to pick image')));
    }
  }

  @override
  void initState() {
    jobs.add(
      JobPhotoPicker(
        jobName: 'Job 1',
        color: selectedJob == 1 ? Colors.blue : Colors.blue[700],
        onSelection: () {
          setState(() {
            selectedJob = 1;
          });
        },
        onTap: () {
          addimages();
        },
      ),
    );
    super.initState();
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
                      Text('Add', style: TextStyle(fontSize: 15)),
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
            children: [Text('Edit Job', style: TextStyle(fontSize: 20))],
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
                  IconButton(onPressed: () {}, icon: Icon(Icons.edit)),
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
