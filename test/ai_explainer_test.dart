import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anthrofit/intelligence/ai_explainer.dart';
import 'package:anthrofit/screens/widgets/ai_explain_button.dart';

const _request = ExplainRequest(
  kind: ExplainKind.coaching,
  facts: ['10 reps, inside the 8–12 target. Keep the same load.'],
  goal: 'Build muscle',
);

class _Fake implements AiExplainer {
  _Fake(this.reply);
  final String? reply;
  int calls = 0;

  @override
  Future<String?> explain(ExplainRequest request) async {
    calls++;
    return validateReply(reply, request);
  }
}

void main() {
  group('prompt and checks', () {
    test('the prompt carries the facts and the rules, not personal data', () {
      final p = buildPrompt(_request);
      expect(p, contains('- 10 reps, inside the 8–12 target'));
      expect(p, contains('Do not add new numbers'));
      expect(p, contains('User goal: Build muscle.'));
    });

    test('nutrition explanations may not suggest foods or plans', () {
      final p = buildPrompt(
        const ExplainRequest(kind: ExplainKind.nutrition, facts: ['x']),
      );
      expect(p, contains('Do not suggest foods'));
    });

    test('a reply with only numbers from the facts is accepted', () {
      expect(
        validateReply('You did 10 reps, inside 8 to 12. Nice.', _request),
        isNotNull,
      );
    });

    test('a reply that invents a number is rejected', () {
      expect(validateReply('Add 5 kg next set.', _request), isNull);
    });

    test('empty or overly long replies are rejected', () {
      expect(validateReply('', _request), isNull);
      expect(validateReply(null, _request), isNull);
      expect(validateReply('a' * (kAiMaxChars + 1), _request), isNull);
    });
  });

  group('Explain more', () {
    Future<void> pump(WidgetTester tester, AiExplainer fake) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AiExplainButton(request: _request, explainer: fake),
            ),
          ),
        );

    testWidgets('nothing is called until tapped; the reply is labelled AI', (
      tester,
    ) async {
      final fake = _Fake('Ten reps sits inside your range, so keep it.');
      await pump(tester, fake);
      expect(fake.calls, 0);
      await tester.tap(find.byKey(const ValueKey('ai-explain')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-explanation')), findsOneWidget);
      expect(find.textContaining('AI explanation'), findsOneWidget);
    });

    testWidgets('a rejected or failed reply falls back quietly', (
      tester,
    ) async {
      await pump(tester, _Fake('Lift 100 kg.'));
      await tester.tap(find.byKey(const ValueKey('ai-explain')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-unavailable')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-explanation')), findsNothing);
    });
  });
}
