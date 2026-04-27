import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/main.dart';

void main() {
  testWidgets('the app starts and names itself', (tester) async {
    await tester.pumpWidget(const TrippingApp());

    expect(find.text('Tripping'), findsOneWidget);
  });
}
