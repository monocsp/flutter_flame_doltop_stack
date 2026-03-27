import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BlownMessage extends StatelessWidget {
  const BlownMessage({required this.onReset, super.key});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFF34343A).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '고민이 바람에 날아갔어요 🍃',
            textAlign: TextAlign.center,
            style: GoogleFonts.caveat(
              fontSize: 38,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '가볍게, 다시 시작해보세요',
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onReset,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFE066),
              foregroundColor: const Color(0xFF2A2A2E),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            child: const Text('새로운 고민 적기'),
          ),
        ],
      ),
    );
  }
}
