import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';

final services = FirebaseServices.instance;

class ExpenseTracker extends StatefulWidget {
  const ExpenseTracker({super.key});
  

  @override
  State<ExpenseTracker> createState() => _ExpenseTrackerState();
}

class _ExpenseTrackerState extends State<ExpenseTracker> {

  @override
  void initState() {
    final jobs = services.getCompanyJobs();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return  Scaffold(
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('-Create PO-------------------', style: TextStyle(fontSize: 18),),
          ),
          Padding(
            padding: EdgeInsets.all(8.0), 
            child: Container(
              decoration: BoxDecoration(color: Colors.white70, border: Border(), borderRadius: BorderRadius.all(Radius.circular(5))),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('Job Name:'),
                      SizedBox(width: 4,),
                      DropdownMenu(dropdownMenuEntries: dropdownMenuEntries)
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Text('Cost Code:'),
                      SizedBox(width: 4,),

                    ],
                  ),
                  SizedBox(height: 10),
                  Row(children: [
                    Text('Date:'),
                    SizedBox(width: 4),
                    final date = DatePickerDialog(firstDate: DateTime(2000), lastDate: DateTime.now(), initialDate: DateTime.now())
                  ],),
                  Row(children: [
                    Text('Amount (inc Tax)'),
                    SizedBox(width: 4),
                    TextField(decoration: kInputDecoration,)
                  ],)
                ],
              )
            ),
          )
        ],
      ),
    );
  }
}