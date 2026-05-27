import 'package:flutter/material.dart';

class ReusableSearchBar extends StatelessWidget {

  final Icon leadingIcon;
  final String hintText;
  final double padding;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;

  const ReusableSearchBar({
    super.key,
    required this.leadingIcon,
    required this.hintText,
    required this.padding,
    required this.onSubmitted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: SearchBar(
        backgroundColor: WidgetStateProperty.all(Colors.grey),
        leading: leadingIcon,
        hintText: hintText,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
      ),
    );
  }
}