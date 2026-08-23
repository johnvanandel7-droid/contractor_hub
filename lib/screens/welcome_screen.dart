import 'package:contractor_hub/components/reusable_button.dart';
import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';

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
      duration: Duration(seconds: 3),
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
                DefaultTextStyle(
                  style: TextStyle(
                    fontSize: 35.0,
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                  ),
                  child: AnimatedTextKit(
                    animatedTexts: [TypewriterAnimatedText('Contractor Hub')],
                  ),
                ),
              ],
            ),
            ReusableButton(
              buttonText: 'Login',
              onPress: () => Navigator.pushNamed(context, '/loginPage'),
              buttonHeight: 50,
              buttonWidth: double.infinity,
              buttonColor: Colors.grey,
              buttonPadding: 20,
            ),
            ReusableButton(
              buttonText: 'Create New Account',
              onPress: () => Navigator.pushNamed(context, '/registerScreen'),
              buttonHeight: 50,
              buttonWidth: double.infinity,
              buttonColor: Colors.blue,
              buttonPadding: 20,
            ),
          ],
        ),
      ),
    );
  }
}
