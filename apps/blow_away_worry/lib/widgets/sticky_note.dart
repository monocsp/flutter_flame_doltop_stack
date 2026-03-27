import 'package:blow_away_worry/widgets/sticky_note_painter.dart';
import 'package:blow_away_worry/widgets/tape_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class StickyNote extends StatelessWidget {
  const StickyNote({
    required this.width,
    required this.height,
    required this.color,
    required this.controller,
    required this.enabled,
    required this.tapeOpacity,
    required this.tapeScaleY,
    required this.shadowLift,
    super.key,
  });

  final double width;
  final double height;
  final Color color;
  final TextEditingController controller;
  final bool enabled;
  final double tapeOpacity;
  final double tapeScaleY;
  final double shadowLift;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height + 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            top: 18,
            child: SizedBox(
              width: width,
              height: height,
              child: CustomPaint(
                painter: StickyNotePainter(
                  color: color,
                  hoverProgress: shadowLift,
                ),
                child: ClipPath(
                  clipper: StickyNoteClipper(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 42, 24, 34),
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(painter: _NoteLinesPainter()),
                          ),
                        ),
                        TextField(
                          controller: controller,
                          enabled: enabled,
                          maxLines: null,
                          expands: true,
                          keyboardType: TextInputType.multiline,
                          style: GoogleFonts.caveat(
                            fontSize: 28,
                            height: 1.32,
                            color: const Color(0xFF2B241F),
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText:
                                '여기에 고민을 적어보세요...\n\n예) 이직을 해야 할까...\n    내가 잘 하고 있는 걸까',
                            hintStyle: GoogleFonts.caveat(
                              fontSize: 26,
                              height: 1.34,
                              color: const Color(
                                0xFF2B241F,
                              ).withValues(alpha: 0.42),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: width * 0.25,
            child: Transform.scale(
              alignment: Alignment.center,
              scaleY: tapeScaleY,
              child: TapeWidget(width: width * 0.3, opacity: tapeOpacity),
            ),
          ),
        ],
      ),
    );
  }
}

class StickyNoteClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => buildStickyNotePath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _NoteLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = const Color(0xFF5D4D40).withValues(alpha: 0.14)
      ..strokeWidth = 1;

    const double topInset = 18;
    const double spacing = 34;
    double y = topInset;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      y += spacing;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
