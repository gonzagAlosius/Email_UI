import 'package:flutter/material.dart';
import 'email_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Email Client App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE0E0E0),
          space: 1,
          thickness: 1,
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const EmailHomeScreen(),
    );
  }
}
