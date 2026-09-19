import 'package:contractor_hub/components/app_bar.dart';
import 'package:flutter/material.dart';

class MileageTracker extends StatelessWidget {
  const MileageTracker({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text('- Create Travel Log ---', style: TextStyle(fontSize: 20)),
            SizedBox(height: 10),
            Container(),
          ],
        ),
      ),
    );
  }
}
