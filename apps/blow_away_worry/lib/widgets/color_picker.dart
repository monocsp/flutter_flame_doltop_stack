import 'package:blow_away_worry/utils/note_colors.dart';
import 'package:flutter/material.dart';

class ColorPicker extends StatelessWidget {
  const ColorPicker({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<NoteColorOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double itemExtent = 42;
        final double requiredHeight = options.length * itemExtent;
        final double availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : requiredHeight;
        return SizedBox(
          width: 40,
          height: availableHeight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List<Widget>.generate(options.length, (int index) {
                final bool selected = index == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: GestureDetector(
                    onTap: () => onSelected(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: selected ? 28 : 22,
                      height: selected ? 28 : 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: options[index].color,
                        border: Border.all(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.35),
                          width: selected ? 3 : 1.4,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: options[index].color.withValues(alpha: 0.42),
                            blurRadius: selected ? 16 : 8,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
