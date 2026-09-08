import 'package:flutter/material.dart';

class CompanyFiles extends StatefulWidget {
  const CompanyFiles({super.key});

  @override
  State<CompanyFiles> createState() => _CompanyFilesState();
}

class _CompanyFilesState extends State<CompanyFiles> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Column(children: [Text('Company Files')]));
  }
}
