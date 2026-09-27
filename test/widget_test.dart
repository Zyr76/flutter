// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Placeholder smoke test', (WidgetTester tester) async {
    final tx = const Text('tuaima');
    await tester.pumpWidget(Center(child: tx));
    expect(find.text('tuaima'), findsOneWidget);
  });
}