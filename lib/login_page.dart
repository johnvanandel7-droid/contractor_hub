import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/reusable_button.dart';
import 'package:contractor_hub/search_bar.dart';
import 'package:flutter/material.dart';

String loginPassword = '';
String loginEmail = '';
String companyName = '';
bool incorrectCompany = true;
bool incorrectEmail = true;
bool incorrectPassword = true;
bool validLogin = false;
String knownCompany = 'h';
String knownPassword = 'i';
// List knownCompany = [
//   'Andel Wood Homes',
//   'JPL golf balls',
// ];
// List knownPassword = [
//   '12345678',
//   'password',
// ];

bool checkIfCorrectLogin () {
  if (companyName == knownCompany) {
    if (loginPassword == knownPassword) {
      if (loginEmail.contains('@')) {
        validLogin = true;
        incorrectEmail = false;
        return true;
      }
      else {
        incorrectEmail = true;
        return false;
      }
    }
    else {
      incorrectPassword = true;
      return false;
    }
  }
  else {
    incorrectCompany = true;
    return false;
  }
}

Text displayLoginInfo() { 
  checkIfCorrectLogin();
  if (incorrectEmail == true && incorrectPassword == true && incorrectCompany == true) {
    return Text(
      'Invalid Information, Try again',
      style: kInvalidLogin,
    );
  }
  else if (incorrectEmail == true) {
    return Text(
      'Invalid Email, Try again',
      style: kInvalidLogin,
    );
  }
  else if (incorrectPassword == true) {
    return Text(
      'Invalid password, Try again',
      style: kInvalidLogin,
    );
  }
  else if (incorrectCompany == true) {
    return Text(
      'Invalid Company, Try again',
      style: kInvalidLogin,
    );
  }
  return Text(loginEmail);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State <LoginPage> createState() => LoginPageState();
}
class LoginPageState extends State <LoginPage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Login Page'
        ),
        elevation: 6,
        shadowColor: Colors.black,
        backgroundColor: Colors.grey,
      ),
      body: Column(
        children: [
          SizedBox(height: 20),
          Text(
            'Login',
            style: kLargeTextSize,
          ),
          ReusableSearchBar(
            leadingIcon: Icon(Icons.house), 
            hintText: 'company', 
            padding: 15,
            onSubmitted: (value) {
              setState(() {
                companyName = value;
              });
              displayLoginInfo();
            },
            onChanged: (value) { 
              setState(() {
                companyName = value;
              });
              displayLoginInfo();
            }
          ),
          ReusableSearchBar(
            leadingIcon: Icon(Icons.email), 
            hintText: 'Email', 
            padding: 15,
            onSubmitted: (value) {
              setState(() {
                loginEmail = value;
              });
              displayLoginInfo();
            },
            onChanged: (value) { 
               setState(() {
                loginEmail = value;
              });
              displayLoginInfo();
            }
          ),
          ReusableSearchBar(
            hintText: 'password',
            leadingIcon: Icon(Icons.password),
            padding: 15,
            onChanged: (value) {
              setState(() {
                loginPassword = value;
              });
              displayLoginInfo();
            },
            onSubmitted: (value) {
              setState(() {
                loginPassword = value;
              });
              displayLoginInfo();
            },
          ),
          Padding(
            padding: EdgeInsetsGeometry.all(10),
            child: displayLoginInfo(), 
          ),
          ReusableButton(
            buttonText: 'Login', 
            onPress: () {
              checkIfCorrectLogin();
              if (validLogin == true) {
                Navigator.pushNamed(context, '/homePage');
              }
            }, 
            buttonHeight: 60,
            buttonWidth: 100, 
            buttonColor: Colors.grey, 
            buttonPadding: 20,
          )
        ],
      )
    );
  }
}