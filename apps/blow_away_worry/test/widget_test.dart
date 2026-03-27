import 'package:blow_away_worry/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders title and idle hint', (WidgetTester tester) async {
    await tester.pumpWidget(const BlowAwayWorryApp());

    expect(find.text('고민을 날려버려'), findsOneWidget);
    expect(find.text('마이크 버튼을 눌러 시작'), findsOneWidget);
  });
}
