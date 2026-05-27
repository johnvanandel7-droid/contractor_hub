import 'package:contractor_hub/constants.dart';
import 'package:flutter/material.dart';

class ReusableButton extends StatelessWidget {

  final String buttonText;
  final VoidCallback onPress;
  final double buttonWidth;
  final double buttonHeight;
  final Color buttonColor;
  final double buttonPadding;

  const ReusableButton({
    super.key, 
    required this.buttonText,
    required this.onPress,
    required this.buttonHeight,
    required this.buttonWidth,
    required this.buttonColor,
    required this.buttonPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(buttonPadding),
      child: RawMaterialButton(
        elevation: 6,
        constraints: BoxConstraints.tightFor(
          width: buttonWidth,
          height: buttonHeight,
        ),
        onPressed: onPress,
        fillColor: buttonColor,
        child: Text(
          buttonText,
          style: kLargeTextSize,
        ),
      ),
    );
  }
}