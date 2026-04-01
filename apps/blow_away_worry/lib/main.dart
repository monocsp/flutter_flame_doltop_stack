import 'package:blow_away_worry/screens/intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BlowAwayWorryApp());
}

class BlowAwayWorryApp extends StatelessWidget {
  const BlowAwayWorryApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData baseTheme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF2A2A2E),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFFE066),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.notoSansKrTextTheme(
          baseTheme.textTheme,
        ).apply(bodyColor: Colors.white, displayColor: Colors.white),
      ),
      home: const IntroScreen(),
    );
  }
}
