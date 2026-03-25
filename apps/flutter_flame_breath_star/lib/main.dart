import 'package:flutter/material.dart';
import 'package:flutter_flame_breath_star/ui/intro_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BreathStarApp());
}

class BreathStarApp extends StatelessWidget {
  const BreathStarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09111F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9EDCFF),
          brightness: Brightness.dark,
        ),
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: const Color(0xFFF7F3E9),
          displayColor: const Color(0xFFF7F3E9),
        ),
      ),
      home: const IntroScreen(),
    );
  }
}
