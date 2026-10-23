import 'package:flutter/material.dart';

/// Asks for a new name, and returns it trimmed, or null if cancelled or
/// unchanged.
///
/// The dialog owns its text controller and disposes it with itself. Creating
/// the controller outside and disposing it as soon as showDialog returns
/// throws, because the dialog is still animating out and still using it.
Future<String?> showRenameDialog(
  BuildContext context, {
  required String title,
  required String current,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(title: title, current: current),
  );
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == current) return null;
  return trimmed;
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.title, required this.current});

  final String title;
  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('rename-field'),
        controller: _field,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_field.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
