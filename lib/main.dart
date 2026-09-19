import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
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
      home: const AuthScreen(),
    );
  }
}
