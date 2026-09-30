import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';

final services = FirebaseServices.instance;

class Contacts extends StatefulWidget {
  const Contacts({super.key});

  @override
  State<Contacts> createState() => _ContactsState();
}

class _ContactsState extends State<Contacts> {
  final uid = services.currentUid;
  String? _companyName;
  bool showCompanyContacts = true;
  List<ContactGroupTemplate> contactGroups = [];

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  Future<void> _loadCompany() async {
    final user = await services.getUser(auth.currentUser!.uid);
    if (mounted) setState(() => _companyName = user?['companyName'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Contacts',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(children: contactGroups),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: TextField(
              decoration: kInputDecoration.copyWith(
                hintText: 'Search Contacts',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ContactGroupTemplate extends StatelessWidget {
  final String groupName;
  const ContactGroupTemplate({super.key, required this.groupName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(10),
      child: GestureDetector(
        onTap: () {},
        child: Container(
          decoration: kboxDecoration,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text(
                  groupName,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ContactTemplate extends StatelessWidget {
  final String contactName;
  final String phoneNumber;
  final String email;
  const ContactTemplate({
    super.key,
    required this.contactName,
    required this.phoneNumber,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: kboxDecoration,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Text(
                'name: $contactName phone number: $phoneNumber email: $email',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
