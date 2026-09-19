import 'package:flutter/material.dart';

void main() {
  runApp(const DalalatShabshaApp());
}

class DalalatShabshaApp extends StatelessWidget {
  const DalalatShabshaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دلالة شبشة',
      theme: ThemeData(
        useMaterial3: true,
      ),
      locale: const Locale('ar'),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('دلالة شبشة'),
        ),
        body: const Center(
          child: Text(
            'مرحباً بك في دلالة شبشة',
            style: TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }
}
