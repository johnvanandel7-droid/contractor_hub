import 'package:contractor_hub/screens/construction_images.dart';
import 'package:contractor_hub/screens/register_screen.dart';
import 'package:contractor_hub/screens/registration_payment_screen.dart';
import 'package:contractor_hub/screens/welcome_screen.dart';
import 'package:contractor_hub/screens/to_do_list.dart';
import 'package:contractor_hub/screens/your_employees_screen.dart';
import 'package:contractor_hub/screens/your_jobs_screen.dart';
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
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Colors.lightBlueAccent,
          onSecondary: Colors.white,
          error: Colors.red,
          onError: Colors.white,
          surface: Colors.white70,
          onSurface: Colors.black,
        ),
      ),
      initialRoute: '/welcomeScreen',
      routes: {
        '/welcomeScreen': (context) => WelcomeScreen(),
        '/loginPage': (context) => LoginScreen(),
        '/homePage': (context) => HomePage(),
        '/clockInOut': (context) => ClockInOut(),
        '/toDoList': (context) => ToDoList(),
        '/registerScreen': (context) => RegistrationScreen(),
        '/registrationPayment': (context) => RegistrationPaymentScreen(),
        '/yourEmployees': (context) => YourEmployeesScreen(),
        '/yourJobs': (context) => YourJobsScreen(),
        '/constructionImages': (context) => ConstructionImages(),
      },
    ),
  );
}
