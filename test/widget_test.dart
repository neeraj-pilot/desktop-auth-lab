import 'package:desktop_auth_lab/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders desktop auth lab shell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const DesktopAuthLabApp());

    expect(find.text('Desktop Auth Lab'), findsWidgets);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('Check support'), findsOneWidget);
    expect(find.byIcon(Icons.fingerprint), findsWidgets);
  });
}
