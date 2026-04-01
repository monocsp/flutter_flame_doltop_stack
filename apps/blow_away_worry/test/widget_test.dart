import 'package:blow_away_worry/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders intro hero title', (WidgetTester tester) async {
    await tester.pumpWidget(const BlowAwayWorryApp());

    expect(find.textContaining('날려버려'), findsOneWidget);
  });
}
