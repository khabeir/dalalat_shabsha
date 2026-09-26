import 'package:flutter/material.dart';

class HomeErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const HomeErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(
            Icons.wifi_off,
            size: 44,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onRetry,
            child: const Text(
              'إعادة المحاولة',
            ),
          ),
        ],
      ),
    );
  }
}
