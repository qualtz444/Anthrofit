import 'package:anthrofit/screens/session/rest_timer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rest timer fits a narrow phone width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 320,
              child: RestTimer(seconds: 90, onSecondsChanged: (_) {}),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
