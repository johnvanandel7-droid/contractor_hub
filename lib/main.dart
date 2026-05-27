import 'package:contractor_hub/welcome%20screen.dart';
import 'package:contractor_hub/to_do_list.dart';
import 'package:flutter/material.dart';
import 'home_page.dart';
import 'clock_in_out.dart';
import 'login_page.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme(
          brightness: Brightness.light,
          primary: Colors.blueAccent,
          onPrimary: Colors.white,
          secondary: Colors.lightBlueAccent,
          onSecondary: Colors.white,
          error: Colors.red,
          onError: Colors.white,
          surface: Colors.blue,
          onSurface: Colors.black,
        ),
      ),
      initialRoute: '/loginOrCreateAccount',
      routes: {
        '/loginOrCreateAccount': (context) => WelcomeScreen(),
        '/loginPage': (context) => LoginPage(),
        '/homePage': (context) => HomePage(),
        '/clockInOut': (context) => ClockInOut(),
        '/toDoList': (context) => ToDoList(),
      },
    ),
  );
}
