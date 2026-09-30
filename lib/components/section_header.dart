import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final bool isExpanded;
  final VoidCallback onToggle;

  const SectionHeader({
    super.key,
    required this.title,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            onPressed: onToggle,
            icon: Icon(
              isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
          ),
        ],
      ),
    );
  }
}
