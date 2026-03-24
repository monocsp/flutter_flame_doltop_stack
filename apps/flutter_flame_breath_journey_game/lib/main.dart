import 'package:flutter/material.dart';
import 'package:flutter_flame_breath_journey_game/ui/intro_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BreathJourneyApp());
}

class BreathJourneyApp extends StatelessWidget {
  const BreathJourneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1F2D),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7ADAA5),
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
