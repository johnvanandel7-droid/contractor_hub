import 'package:flutter/material.dart';

// ignore: must_be_immutable
class ReusableIconButton extends StatelessWidget {
  VoidCallback onPressed;
  Icon icon;

  ReusableIconButton({super.key, required this.onPressed, required this.icon});

  final iconColor = Colors.black;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      onPressed: onPressed,
      color: iconColor,
      iconSize: 30,
      highlightColor: Colors.grey[800],
      onLongPress: onPressed,
      padding: EdgeInsets.all(10),
    );
  }
}
