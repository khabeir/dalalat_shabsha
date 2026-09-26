import 'package:flutter/material.dart';

class HomeGreeting extends StatelessWidget {
  final String name;

  const HomeGreeting({
    super.key,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        0,
        20,
        8,
      ),
      child: Text(
        'مرحباً يا $name 👋',
        style: TextStyle(
          fontSize: 13.5,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
      ),
    );
  }
}
