import 'package:contractor_hub/components/app_bar.dart';
import 'package:flutter/material.dart';

class QuickbooksConnection extends StatelessWidget {
  const QuickbooksConnection({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(),
      body: Column(children: [Text('Connect to quickbooks')],),
    );
  }
}