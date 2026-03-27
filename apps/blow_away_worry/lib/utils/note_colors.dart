import 'package:flutter/material.dart';

class NoteColorOption {
  const NoteColorOption({required this.name, required this.color});

  final String name;
  final Color color;
}

class NoteColors {
  static const List<NoteColorOption> palette = <NoteColorOption>[
    NoteColorOption(name: '노랑', color: Color(0xFFFFE066)),
    NoteColorOption(name: '분홍', color: Color(0xFFFF9AA2)),
    NoteColorOption(name: '파랑', color: Color(0xFFA0D8EF)),
    NoteColorOption(name: '초록', color: Color(0xFFB5EAD7)),
    NoteColorOption(name: '주황', color: Color(0xFFFFB347)),
  ];
}
