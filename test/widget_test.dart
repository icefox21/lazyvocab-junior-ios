import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_player/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LazyVocabApp());
    expect(find.byType(LazyVocabApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
