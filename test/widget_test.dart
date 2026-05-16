import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_library/app.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const LocalLibraryApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
