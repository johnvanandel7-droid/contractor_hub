import 'package:contractor_hub/screens/welcome%20screen.dart';
import 'package:contractor_hub/screens/to_do_list.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'screens/home_page.dart';
import 'screens/clock_in_out.dart';
import 'screens/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
        '/loginPage': (context) => LoginScreen(),
        '/homePage': (context) => HomePage(),
        '/clockInOut': (context) => ClockInOut(),
        '/toDoList': (context) => ToDoList(),
      },
    ),
  );
}
