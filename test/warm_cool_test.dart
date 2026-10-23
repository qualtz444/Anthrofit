import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anthrofit/coaching/warm_cool.dart';
import 'package:anthrofit/models/models.dart';
import 'package:anthrofit/screens/session/warm_cool_card.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: ListView(children: [child])));

String _clock(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('warm-cool-clock'))).data!;

void main() {
  testWidgets('warm-up card: timer counts down, +1 min adds, Hide calls back', (
    tester,
  ) async {
    var hidden = false;
    await tester.pumpWidget(
      _host(
        WarmCoolCard(
          kind: WarmCoolKind.warmUp,
          onHide: () => hidden = true,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('warm-up-card')), findsOneWidget);
    expect(find.text('Warm up first'), findsOneWidget);
    expect(_clock(tester), '05:00');

    await tester.tap(find.byKey(const ValueKey('warm-cool-timer')));
    await tester.pump(const Duration(seconds: 3));
    expect(_clock(tester), '04:57');
    expect(find.text('Pause timer'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('warm-cool-timer')));
    await tester.pump(const Duration(seconds: 3));
    expect(_clock(tester), '04:57', reason: 'paused');

    await tester.tap(find.byKey(const ValueKey('warm-cool-more')));
    await tester.pump();
    expect(_clock(tester), '05:57');

    await tester.tap(find.byKey(const ValueKey('warm-cool-hide')));
    expect(hidden, isTrue);
  });

  testWidgets('cool-down card names the muscles trained', (tester) async {
    await tester.pumpWidget(
      _host(
        WarmCoolCard(
          kind: WarmCoolKind.coolDown,
          muscles: const [MuscleGroup.chest],
          onHide: () {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('cool-down-card')), findsOneWidget);
    expect(
      find.text('Trained today: ${MuscleGroup.chest.label}'),
      findsOneWidget,
    );
  });

  test('the setting is saved and read back', () async {
    SharedPreferences.setMockInitialValues({});
    final a = WarmCoolSettings();
    await a.load();
    expect(a.value, isTrue, reason: 'on by default');
    await a.set(false);

    final b = WarmCoolSettings();
    await b.load();
    expect(b.value, isFalse);
  });
}
