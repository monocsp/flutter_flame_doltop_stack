import 'package:flutter/material.dart';

class MicButton extends StatelessWidget {
  const MicButton({
    required this.isActive,
    required this.pulse,
    required this.onTap,
    super.key,
  });

  final bool isActive;
  final double pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double ringScale = 1 + pulse * 0.18;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 108,
        height: 108,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (isActive)
              Transform.scale(
                scale: ringScale,
                child: Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFE066).withValues(alpha: 0.35),
                      width: 2,
                    ),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isActive
                      ? const <Color>[Color(0xFFFFC94A), Color(0xFFFF8E5E)]
                      : const <Color>[Color(0xFF54545D), Color(0xFF3B3B42)],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: (isActive ? const Color(0xFFFFC94A) : Colors.black)
                        .withValues(alpha: isActive ? 0.36 : 0.22),
                    blurRadius: isActive ? 24 : 14,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(
                isActive ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
