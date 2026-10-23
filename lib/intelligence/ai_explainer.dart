import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

/// The ANTHROFIT Intelligence Layer's only AI entry point.
///
/// The AI never calculates. It receives findings the app has ALREADY worked
/// out (coaching lines, insights, prescription reasons) and rewords them in
/// plain language. Its reply is checked before it is shown, and any failure
/// returns null so the screen keeps the rule-based text. Nothing it says is
/// saved, and it can never change a plan, a target or a log.
///
/// No name, email, photo or raw history is sent: only the findings and the
/// goal and experience labels.

/// The Gemini model. Use the same one you tested the connection with.
const String kGeminiModel = 'gemini-3.8-flash';

/// Longest wait before giving up and keeping the rule-based text.
///
/// App design value, not from a source. Raised from 15 s because replies
/// were timing out in testing; the rule-based text is on screen meanwhile,
/// so a longer wait only delays the reworded version.
const Duration kAiTimeout = Duration(seconds: 30);

/// Longest reply shown; anything longer is treated as off-task.
const int kAiMaxChars = 900;

enum ExplainKind { coaching, insights, tutorial, nutrition }

class ExplainRequest {
  const ExplainRequest({
    required this.kind,
    required this.facts,
    this.goal,
    this.experience,
  });

  final ExplainKind kind;

  /// Findings already computed by the app, one per entry.
  final List<String> facts;

  /// Labels only, e.g. "Build muscle", "Beginner".
  final String? goal;
  final String? experience;
}

abstract class AiExplainer {
  /// A checked explanation, or null when unavailable or rejected.
  Future<String?> explain(ExplainRequest request);
}

/// Builds the prompt. Public so it can be tested without a network.
String buildPrompt(ExplainRequest r) {
  final task = switch (r.kind) {
    ExplainKind.coaching =>
      'Explain this coaching feedback about the set the user just finished.',
    ExplainKind.insights =>
      'Explain what these progress findings mean for the user.',
    ExplainKind.nutrition =>
      'Explain these daily nutrition targets and how they relate to the '
          "user's goal. Do not suggest foods, meal plans or supplements.",
    ExplainKind.tutorial =>
      'Explain why this exercise and its sets, reps and rest are in the '
          "user's program.",
  };
  return [
    "You are ANTHROFIT's training assistant for adult gym users.",
    task,
    'Rules:',
    '- Use ONLY the facts below. Do not add new numbers, targets, loads, '
        'calories or time frames.',
    '- Keep any uncertainty the facts state. Never call an estimate exact.',
    '- No medical diagnosis or treatment. Do not claim to see the user\'s '
        'technique or form.',
    '- If a fact mentions pain, dizziness or discomfort, tell them to stop.',
    '- 2 to 4 short sentences, plain English, no headings or lists.',
    if (r.goal != null) 'User goal: ${r.goal}.',
    if (r.experience != null) 'Experience: ${r.experience}.',
    'Facts:',
    for (final f in r.facts) '- $f',
  ].join('\n');
}

final RegExp _number = RegExp(r'\d+(?:\.\d+)?');

/// Checks a reply before it is shown. Returns the cleaned text or null.
///
/// The key check: every number in the reply must already appear in the facts
/// (or the goal/experience labels). That stops the AI from inventing a
/// target, a load or a statistic, which is what the panel's spec forbids.
String? validateReply(String? reply, ExplainRequest r) {
  final text = reply?.trim();
  if (text == null || text.isEmpty || text.length > kAiMaxChars) return null;
  final source = [...r.facts, r.goal ?? '', r.experience ?? ''].join(' ');
  final allowed = _number.allMatches(source).map((m) => m.group(0)).toSet();
  for (final m in _number.allMatches(text)) {
    if (!allowed.contains(m.group(0))) return null;
  }
  return text;
}

/// Gemini through Firebase AI Logic (App Check is applied automatically).
///
/// The model is created on first use, not at startup, so app launch never
/// waits on (or fails because of) the AI.
class GeminiExplainer implements AiExplainer {
  GenerativeModel? _model;

  // App Check is picked up automatically from main.dart's activation.
  GenerativeModel _modelOrCreate() =>
      _model ??= FirebaseAI.googleAI().generativeModel(model: kGeminiModel);

  @override
  Future<String?> explain(ExplainRequest request) async {
    if (request.facts.isEmpty) return null;
    final clock = Stopwatch()..start();
    try {
      final response = await _modelOrCreate()
          .generateContent([Content.text(buildPrompt(request))])
          .timeout(kAiTimeout);
      // Debug builds only: how long Gemini took, to tune kAiTimeout.
      debugPrint('[AI] reply after ${clock.elapsedMilliseconds} ms');
      final checked = validateReply(response.text, request);
      if (checked == null) {
        // Debug builds only: shows why a reply was refused.
        debugPrint('[AI] reply rejected by validation: ${response.text}');
      }
      return checked;
    } catch (e) {
      // Offline, App Check, quota, timeout: the rule-based text stays.
      debugPrint(
        '[AI] request failed after ${clock.elapsedMilliseconds} ms: $e',
      );
      return null;
    }
  }
}

/// The explainer screens use. Tests can swap it for a fake.
AiExplainer aiExplainer = GeminiExplainer();
