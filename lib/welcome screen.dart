import 'package:contractor_hub/reusable_button.dart';
import 'package:flutter/material.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? controller;
  Animation? animation;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );

    animation = ColorTween(
      begin: Colors.blueGrey,
      end: Colors.white,
    ).animate(controller!);

    controller?.forward();

    controller?.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    controller!.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: animation!.value,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Hero(
                  tag: 'contractor',
                  child: SizedBox(
                    height: 60,
                    child: Image.asset('images/contractor.png'),
                  ),
                ),
                SizedBox(width: 10),
                Text('Contractor Hub', style: TextStyle(fontSize: 20)),
              ],
            ),
            Expanded(
              child: ReusableButton(
                buttonText: 'Login',
                onPress: () => Navigator.pushNamed(context, '/loginPage'),
                buttonHeight: 30,
                buttonWidth: double.infinity,
                buttonColor: Colors.white,
                buttonPadding: 20,
              ),
            ),
            Expanded(
              child: ReusableButton(
                buttonText: 'Create New Account',
                onPress: () =>
                    Navigator.pushNamed(context, '/createNewAccount'),
                buttonHeight: 30,
                buttonWidth: double.infinity,
                buttonColor: Colors.white,
                buttonPadding: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
