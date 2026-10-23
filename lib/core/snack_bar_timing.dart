/// How long a message bar stays before it goes by itself. App design value.
///
/// Message bars without a button use this and close themselves. Bars with
/// an Undo button stay until the user acts or closes them.
const Duration kSnackBarDuration = Duration(seconds: 3);
