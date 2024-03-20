import "../data_io/file/file_selection.dart";

class Searchable {
  /// Map prefix to list of index of appearance in [text]
  ///
  /// If there multiple matches of the same prefix, the mapped value is -1
  ///
  /// Prefix will continue to extend until the appearance is unique
  final map = <String, int>{};

  final String text;

  Searchable(String text) : text = String.fromCharCodes(getRunesForSort(text)) {
    /// Simultaneously start iterating from all positions, and increase
    /// prefix length at each step
    ///
    /// [startIndices] contains the indices from which the prefix may not be
    /// unique. If a prefix becomes unique at a certain length, the index is
    /// stored to [map] and removed from [startIndices]
    ///
    /// This algorithm is O(n^2) in the worst case (when the text is all the
    /// same character)
    var startIndices = List.generate(this.text.length, (i) => i);
    for (var prefixLength = 1; startIndices.isNotEmpty; prefixLength += 1) {
      // get the prefix of each index
      final mapping = Map<int, String>.fromIterable(
        startIndices.where((index) => index + prefixLength <= this.text.length),
        value: (index) => this.text.substring(index, index + prefixLength),
      );
      // count the number of appearances of each prefix
      final counter = <String, int>{};
      for (final prefix in mapping.values) {
        counter.update(prefix, (value) => value + 1, ifAbsent: () => 1);
      }
      startIndices.clear();
      mapping.forEach((index, prefix) {
        if (counter[prefix] == 1) {
          map[prefix] = index;
        } else {
          map[prefix] = -1;
          startIndices.add(index);
        }
      });
    }
  }

  /// Check if [term] is a substring of [text]
  bool contains(String term) {
    term = term.toLowerCase();
    if (term.isEmpty || map.containsKey(term)) {
      return true;
    }

    /// Start checking prefix from length 1
    for (var prefixLength = 1; prefixLength <= term.length; prefixLength += 1) {
      final prefix = term.substring(0, prefixLength);
      final appearance = map[prefix];
      if (appearance == null) {
        return false;
      } else if (appearance == -1) {
        continue;
      } else {
        return appearance + term.length <= text.length &&
            text.substring(appearance, appearance + term.length) == term;
      }
    }
    return false;
  }
}
