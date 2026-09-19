import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
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
