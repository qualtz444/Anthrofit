import '../core/json_utils.dart';

/// Which way the person faces in a progress photo, so like can be compared
/// with like. App design choice.
enum PhotoPose {
  front('Front'),
  side('Side'),
  back('Back'),
  other('Other');

  const PhotoPose(this.label);
  final String label;
}

/// One progress photo the user took or picked: a normal colour photo, not
/// the scan's black and white outline.
///
/// PRIVACY: the picture itself is a file on this phone only. It is never
/// synced; it leaves the phone only when the user shares it in a post.
class ProgressPhoto {
  const ProgressPhoto({
    required this.id,
    required this.takenAt,
    required this.pose,
    this.note = '',
  });

  final String id;
  final DateTime takenAt;
  final PhotoPose pose;

  /// What the user wrote with it. Empty when nothing.
  final String note;

  /// Longest note accepted. App design value.
  static const int maxNote = 200;

  ProgressPhoto copyWith({DateTime? takenAt, PhotoPose? pose, String? note}) =>
      ProgressPhoto(
        id: id,
        takenAt: takenAt ?? this.takenAt,
        pose: pose ?? this.pose,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'takenAt': takenAt.toIso8601String(),
    'pose': pose.name,
    if (note.isNotEmpty) 'note': note,
  };

  /// Null when the entry has no id or no date: it could never be shown.
  static ProgressPhoto? fromJson(Map<String, dynamic> json) {
    final id = parseString(json['id']);
    final takenAt = parseDate(json['takenAt']);
    if (id.isEmpty || takenAt == null) return null;
    return ProgressPhoto(
      id: id,
      takenAt: takenAt,
      pose: enumByName(PhotoPose.values, json['pose'], PhotoPose.other),
      note: parseString(json['note']),
    );
  }
}
