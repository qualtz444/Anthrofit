import '../core/json_utils.dart';
import '../data/ready_made_programs.dart';
import '../models/models.dart';
import '../recommendation/proportion_rules.dart';
import '../recommendation/recommendation_weights.dart';

// What an admin can change from the admin web panel, in the shape it is
// stored in Firestore and cached on the phone.
//
// Everything here is OPTIONAL on top of what ships with the app. A field
// that is missing or empty means "use the built-in value", so a phone that
// never reaches Firestore behaves exactly as before.

/// A piece of equipment an admin added. Built-in equipment stays the
/// [EquipmentItem] enum; these are extra, referred to by [id].
class EquipmentDef {
  const EquipmentDef({
    required this.id,
    required this.label,
    required this.categories,
    this.hidden = false,
  });

  /// Stable id, lowercase letters, numbers and _. Saved in exercises and
  /// program setups, so it never changes once created.
  final String id;
  final String label;

  /// Every place that has it, like [EquipmentItem.categories].
  final Set<EquipmentCategory> categories;

  /// Hidden from the equipment questions. Exercises that need it keep it.
  final bool hidden;

  EquipmentDef copyWith({
    String? label,
    Set<EquipmentCategory>? categories,
    bool? hidden,
  }) => EquipmentDef(
    id: id,
    label: label ?? this.label,
    categories: categories ?? this.categories,
    hidden: hidden ?? this.hidden,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'categories': categories.map((c) => c.name).toList(),
    'hidden': hidden,
  };

  factory EquipmentDef.fromJson(Map<String, dynamic> json) => EquipmentDef(
    id: parseString(json['id']),
    label: parseString(json['label']),
    categories: enumListByName(
      EquipmentCategory.values,
      json['categories'],
    ).toSet(),
    hidden: json['hidden'] == true,
  );
}

/// An admin's replacement for one ratio's cut-offs. [source] is required:
/// a cut-off without a stated source is not accepted by the panel.
class ThresholdOverride {
  const ThresholdOverride({
    required this.low,
    required this.high,
    required this.source,
  });

  final double low;
  final double high;

  /// Where the numbers come from, in the admin's words.
  final String source;

  RatioThreshold get threshold => RatioThreshold(low: low, high: high);

  Map<String, dynamic> toJson() => {
    'low': low,
    'high': high,
    'source': source,
  };

  static ThresholdOverride? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final low = parseNullableDouble(raw['low']);
    final high = parseNullableDouble(raw['high']);
    final source = parseString(raw['source']).trim();
    if (low == null || high == null || low > high || source.isEmpty) {
      return null;
    }
    return ThresholdOverride(low: low, high: high, source: source);
  }
}

/// A proportion rule an admin wrote. Unlike the built-in rules, which match
/// exercises by pattern and equipment, it names the exercises it applies to.
class AdminProportionRule {
  const AdminProportionRule({
    required this.id,
    required this.name,
    required this.ratioKey,
    required this.whenClass,
    required this.scoreDelta,
    required this.exerciseIds,
    required this.rationale,
    this.cue,
    this.reason,
    this.enabled = true,
  });

  final String id;
  final String name;

  /// One of [RatioKeys].
  final String ratioKey;

  /// The class this advice is for.
  final ProportionClass whenClass;

  /// -1 to 1, scaled by the proportion weight, like the built-in rules.
  final double scoreDelta;

  final List<String> exerciseIds;

  /// Why the rule exists, in the admin's words. Required by the panel.
  final String rationale;

  final String? cue;
  final String? reason;
  final bool enabled;

  ProportionRule toRule() => ProportionRule(
    name: name,
    ratioKey: ratioKey,
    appliesTo: (e) => exerciseIds.contains(e.id),
    advice: {
      whenClass: ProportionAdvice(
        scoreDelta: scoreDelta.clamp(-1.0, 1.0),
        cue: cue,
        reason: reason,
      ),
    },
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ratioKey': ratioKey,
    'whenClass': whenClass.name,
    'scoreDelta': scoreDelta,
    'exerciseIds': exerciseIds,
    'rationale': rationale,
    'cue': cue,
    'reason': reason,
    'enabled': enabled,
  };

  factory AdminProportionRule.fromJson(Map<String, dynamic> json) {
    String? optional(Object? raw) {
      final s = parseString(raw).trim();
      return s.isEmpty ? null : s;
    }

    final ids = json['exerciseIds'];
    return AdminProportionRule(
      id: parseString(json['id']),
      name: parseString(json['name']),
      ratioKey: parseString(json['ratioKey']),
      whenClass: enumByName(
        ProportionClass.values,
        json['whenClass'],
        ProportionClass.unknown,
      ),
      scoreDelta: parseDouble(json['scoreDelta']).clamp(-1.0, 1.0),
      exerciseIds: ids is List ? ids.whereType<String>().toList() : const [],
      rationale: parseString(json['rationale']),
      cue: optional(json['cue']),
      reason: optional(json['reason']),
      enabled: json['enabled'] != false,
    );
  }
}

/// The admin's recommendation settings: one Firestore document,
/// content/config.
class ContentConfig {
  const ContentConfig({
    this.weights,
    this.thresholds = const {},
    this.templateExercises = const {},
    this.readyMade,
    this.goalFit = const {},
    this.proportionRules = const [],
    this.disabledRules = const {},
    this.updatedAt,
    this.updatedBy,
  });

  /// Null means the built-in [RecommendationWeights.standard].
  final RecommendationWeights? weights;

  /// Per ratio id. A ratio left out keeps the built-in cut-off.
  final Map<String, ThresholdOverride> thresholds;

  /// Per [WorkoutTemplate] name, the exercise ids it starts with.
  final Map<String, List<String>> templateExercises;

  /// Null means the built-in [kReadyMadePrograms].
  final List<ReadyMadeProgram>? readyMade;

  /// Per exercise id, per [TrainingGoal] name, a fit from 0 to 1 that
  /// replaces the built-in goal heuristic for that exercise.
  final Map<String, Map<String, double>> goalFit;

  final List<AdminProportionRule> proportionRules;

  /// Names of built-in proportion rules that are switched off.
  final Set<String> disabledRules;

  final DateTime? updatedAt;
  final String? updatedBy;

  static const ContentConfig empty = ContentConfig();

  /// A changed copy. [clearWeights] and [clearReadyMade] go back to the
  /// built-in values, which a null argument cannot say.
  ContentConfig copyWith({
    RecommendationWeights? weights,
    bool clearWeights = false,
    Map<String, ThresholdOverride>? thresholds,
    Map<String, List<String>>? templateExercises,
    List<ReadyMadeProgram>? readyMade,
    bool clearReadyMade = false,
    Map<String, Map<String, double>>? goalFit,
    List<AdminProportionRule>? proportionRules,
    Set<String>? disabledRules,
    DateTime? updatedAt,
    String? updatedBy,
  }) => ContentConfig(
    weights: clearWeights ? null : (weights ?? this.weights),
    thresholds: thresholds ?? this.thresholds,
    templateExercises: templateExercises ?? this.templateExercises,
    readyMade: clearReadyMade ? null : (readyMade ?? this.readyMade),
    goalFit: goalFit ?? this.goalFit,
    proportionRules: proportionRules ?? this.proportionRules,
    disabledRules: disabledRules ?? this.disabledRules,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );

  Map<String, dynamic> toJson() => {
    'weights': weights?.toJson(),
    'thresholds': {
      for (final e in thresholds.entries) e.key: e.value.toJson(),
    },
    'templateExercises': templateExercises,
    'readyMade': readyMade?.map((r) => r.toJson()).toList(),
    'goalFit': goalFit,
    'proportionRules': proportionRules.map((r) => r.toJson()).toList(),
    'disabledRules': disabledRules.toList(),
    'updatedAt': updatedAt?.toIso8601String(),
    'updatedBy': updatedBy,
  };

  factory ContentConfig.fromJson(Map<String, dynamic> json) {
    final weights = json['weights'];
    final thresholds = <String, ThresholdOverride>{};
    final rawThresholds = json['thresholds'];
    if (rawThresholds is Map) {
      for (final e in rawThresholds.entries) {
        final t = ThresholdOverride.fromJson(e.value);
        if (e.key is String && t != null) thresholds[e.key as String] = t;
      }
    }

    final templates = <String, List<String>>{};
    final rawTemplates = json['templateExercises'];
    if (rawTemplates is Map) {
      for (final e in rawTemplates.entries) {
        if (e.key is String && e.value is List) {
          templates[e.key as String] = (e.value as List)
              .whereType<String>()
              .toList();
        }
      }
    }

    final goalFit = <String, Map<String, double>>{};
    final rawFit = json['goalFit'];
    if (rawFit is Map) {
      for (final e in rawFit.entries) {
        if (e.key is! String || e.value is! Map) continue;
        final perGoal = <String, double>{};
        for (final g in (e.value as Map).entries) {
          if (g.key is String && g.value is num) {
            perGoal[g.key as String] = (g.value as num).toDouble().clamp(
              0.0,
              1.0,
            );
          }
        }
        if (perGoal.isNotEmpty) goalFit[e.key as String] = perGoal;
      }
    }

    final rawReady = json['readyMade'];
    final disabled = json['disabledRules'];
    return ContentConfig(
      weights: weights is Map
          ? RecommendationWeights.fromJson(Map<String, dynamic>.from(weights))
          : null,
      thresholds: thresholds,
      templateExercises: templates,
      readyMade: rawReady is List
          ? parseMapList(rawReady).map(ReadyMadeProgram.fromJson).toList()
          : null,
      goalFit: goalFit,
      proportionRules: parseMapList(json['proportionRules'])
          .map(AdminProportionRule.fromJson)
          .where((r) => r.id.isNotEmpty && r.ratioKey.isNotEmpty)
          .toList(),
      disabledRules: disabled is List
          ? disabled.whereType<String>().toSet()
          : const <String>{},
      updatedAt: parseDate(json['updatedAt']),
      updatedBy: json['updatedBy'] is String
          ? json['updatedBy'] as String
          : null,
    );
  }
}

/// One exercise as stored by the admin: a full exercise plus whether it is
/// hidden. A doc whose id matches a built-in exercise replaces it.
class ExerciseOverride {
  const ExerciseOverride(this.exercise, {this.hidden = false});

  final Exercise exercise;

  /// Hidden from browsing and recommendations. Programs that already use it
  /// still find it by id.
  final bool hidden;

  Map<String, dynamic> toJson() => {...exercise.toJson(), 'hidden': hidden};

  factory ExerciseOverride.fromJson(Map<String, dynamic> json) =>
      ExerciseOverride(Exercise.fromJson(json), hidden: json['hidden'] == true);
}

/// Everything the admin panel controls, read in one go.
class ContentSnapshot {
  const ContentSnapshot({
    this.config = ContentConfig.empty,
    this.equipment = const [],
    this.exercises = const [],
  });

  final ContentConfig config;
  final List<EquipmentDef> equipment;
  final List<ExerciseOverride> exercises;

  static const ContentSnapshot empty = ContentSnapshot();

  Map<String, dynamic> toJson() => {
    'config': config.toJson(),
    'equipment': equipment.map((e) => e.toJson()).toList(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  factory ContentSnapshot.fromJson(Map<String, dynamic> json) {
    final config = json['config'];
    return ContentSnapshot(
      config: config is Map
          ? ContentConfig.fromJson(Map<String, dynamic>.from(config))
          : ContentConfig.empty,
      equipment: parseMapList(json['equipment'])
          .map(EquipmentDef.fromJson)
          .where((e) => e.id.isNotEmpty)
          .toList(),
      exercises: parseMapList(json['exercises'])
          .map(ExerciseOverride.fromJson)
          .where((e) => e.exercise.id.isNotEmpty)
          .toList(),
    );
  }
}
