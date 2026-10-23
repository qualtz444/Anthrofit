/// Returns a new list with one item moved.
/// Uses the index rules of ReorderableListView.onReorderItem: [newIndex] is
/// the item's final position in the list.
List<T> reorderList<T>(List<T> items, int oldIndex, int newIndex) {
  final result = [...items];
  final moved = result.removeAt(oldIndex);
  result.insert(newIndex, moved);
  return result;
}
