// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' show max;

import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

import '../convert.dart';
import '../globals.dart' as globals;
import 'file_system.dart';

/// Convert `foo_bar` to `fooBar`.
String camelCase(String str) {
  int index = str.indexOf('_');
  while (index != -1 && index < str.length - 2) {
    str = str.substring(0, index) +
      str.substring(index + 1, index + 2).toUpperCase() +
      str.substring(index + 2);
    index = str.indexOf('_');
  }
  return str;
}

final RegExp _upperRegex = RegExp(r'[A-Z]');

/// Convert `fooBar` to `foo_bar`.
String snakeCase(String str, [ String sep = '_' ]) {
  return str.replaceAllMapped(_upperRegex,
      (Match m) => '${m.start == 0 ? '' : sep}${m[0].toLowerCase()}');
}

String toTitleCase(String str) {
  if (str.isEmpty) {
    return str;
  }
  return str.substring(0, 1).toUpperCase() + str.substring(1);
}

/// Return the plural of the given word (`cat(s)`).
String pluralize(String word, int count) => count == 1 ? word : word + 's';

/// Return the name of an enum item.
String getEnumName(dynamic enumItem) {
  final String name = '$enumItem';
  final int index = name.indexOf('.');
  return index == -1 ? name : name.substring(index + 1);
}

String toPrettyJson(Object jsonable) {
  return const JsonEncoder.withIndent('  ').convert(jsonable) + '\n';
}

final NumberFormat kSecondsFormat = NumberFormat('0.0');
final NumberFormat kMillisecondsFormat = NumberFormat.decimalPattern();

String getElapsedAsSeconds(Duration duration) {
  final double seconds = duration.inMilliseconds / Duration.millisecondsPerSecond;
  return '${kSecondsFormat.format(seconds)}s';
}

String getElapsedAsMilliseconds(Duration duration) {
  return '${kMillisecondsFormat.format(duration.inMilliseconds)}ms';
}

/// Return a String - with units - for the size in MB of the given number of bytes.
String getSizeAsMB(int bytesLength) {
  return '${(bytesLength / (1024 * 1024)).toStringAsFixed(1)}MB';
}

/// A class to maintain a list of items, fire events when items are added or
/// removed, and calculate a diff of changes when a new list of items is
/// available.
class ItemListNotifier<T> {
  ItemListNotifier() {
    _items = <T>{};
  }

  ItemListNotifier.from(List<T> items) {
    _items = Set<T>.from(items);
  }

  Set<T> _items;

  final StreamController<T> _addedController = StreamController<T>.broadcast();
  final StreamController<T> _removedController = StreamController<T>.broadcast();

  Stream<T> get onAdded => _addedController.stream;
  Stream<T> get onRemoved => _removedController.stream;

  List<T> get items => _items.toList();

  void updateWithNewList(List<T> updatedList) {
    final Set<T> updatedSet = Set<T>.from(updatedList);

    final Set<T> addedItems = updatedSet.difference(_items);
    final Set<T> removedItems = _items.difference(updatedSet);

    _items = updatedSet;

    addedItems.forEach(_addedController.add);
    removedItems.forEach(_removedController.add);
  }

  /// Close the streams.
  void dispose() {
    _addedController.close();
    _removedController.close();
  }
}

class SettingsFile {
  SettingsFile();

  SettingsFile.parse(String contents) {
    for (String line in contents.split('\n')) {
      line = line.trim();
      if (line.startsWith('#') || line.isEmpty) {
        continue;
      }
      final int index = line.indexOf('=');
      if (index != -1) {
        values[line.substring(0, index)] = line.substring(index + 1);
      }
    }
  }

  factory SettingsFile.parseFromFile(File file) {
    return SettingsFile.parse(file.readAsStringSync());
  }

  final Map<String, String> values = <String, String>{};

  void writeContents(File file) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(values.keys.map<String>((String key) {
      return '$key=${values[key]}';
    }).join('\n'));
  }
}

/// Given a data structure which is a Map of String to dynamic values, return
/// the same structure (`Map<String, dynamic>`) with the correct runtime types.
Map<String, dynamic> castStringKeyedMap(dynamic untyped) {
  final Map<dynamic, dynamic> map = untyped as Map<dynamic, dynamic>;
  return map?.cast<String, dynamic>();
}

typedef AsyncCallback = Future<void> Function();

/// Returns a [Future] that completes when all given [Future]s complete.
///
/// Uses [Future.wait] but removes null elements from the provided
/// `futures` iterable first.
///
/// The returned [Future<List>] will be shorter than the given `futures` if
/// it contains nulls.
Future<List<T>> waitGroup<T>(Iterable<Future<T>> futures) {
  return Future.wait<T>(futures.where((Future<T> future) => future != null));
}

/// Smallest column that will be used for text wrapping. If the requested column
/// width is smaller than this, then this is what will be used.
const int kMinColumnWidth = 10;

/// Wraps a block of text into lines no longer than [columnWidth].
///
/// Tries to split at whitespace, but if that's not good enough to keep it
/// under the limit, then it splits in the middle of a word. If [columnWidth] is
/// smaller than 10 columns, will wrap at 10 columns.
///
/// Preserves indentation (leading whitespace) for each line (delimited by '\n')
/// in the input, and will indent wrapped lines that same amount, adding
/// [indent] spaces in addition to any existing indent.
///
/// If [hangingIndent] is supplied, then that many additional spaces will be
/// added to each line, except for the first line. The [hangingIndent] is added
/// to the specified [indent], if any. This is useful for wrapping
/// text with a heading prefix (e.g. "Usage: "):
///
/// ```dart
/// String prefix = "Usage: ";
/// print(prefix + wrapText(invocation, indent: 2, hangingIndent: prefix.length, columnWidth: 40));
/// ```
///
/// yields:
/// ```
///   Usage: app main_command <subcommand>
///          [arguments]
/// ```
///
/// If [columnWidth] is not specified, then the column width will be the
/// [outputPreferences.wrapColumn], which is set with the --wrap-column option.
///
/// If [outputPreferences.wrapText] is false, then the text will be returned
/// unchanged. If [shouldWrap] is specified, then it overrides the
/// [outputPreferences.wrapText] setting.
///
/// The [indent] and [hangingIndent] must be smaller than [columnWidth] when
/// added together.
String wrapText(String text, { int columnWidth, int hangingIndent, int indent, bool shouldWrap }) {
  if (text == null || text.isEmpty) {
    return '';
  }
  indent ??= 0;
  columnWidth ??= globals.outputPreferences.wrapColumn;
  columnWidth -= indent;
  assert(columnWidth >= 0);

  hangingIndent ??= 0;
  final List<String> splitText = text.split('\n');
  final List<String> result = <String>[];
  for (final String line in splitText) {
    String trimmedText = line.trimLeft();
    final String leadingWhitespace = line.substring(0, line.length - trimmedText.length);
    List<String> notIndented;
    if (hangingIndent != 0) {
      // When we have a hanging indent, we want to wrap the first line at one
      // width, and the rest at another (offset by hangingIndent), so we wrap
      // them twice and recombine.
      final List<String> firstLineWrap = _wrapTextAsLines(
        trimmedText,
        columnWidth: columnWidth - leadingWhitespace.length,
        shouldWrap: shouldWrap,
      );
      notIndented = <String>[firstLineWrap.removeAt(0)];
      trimmedText = trimmedText.substring(notIndented[0].length).trimLeft();
      if (firstLineWrap.isNotEmpty) {
        notIndented.addAll(_wrapTextAsLines(
          trimmedText,
          columnWidth: columnWidth - leadingWhitespace.length - hangingIndent,
          shouldWrap: shouldWrap,
        ));
      }
    } else {
      notIndented = _wrapTextAsLines(
        trimmedText,
        columnWidth: columnWidth - leadingWhitespace.length,
        shouldWrap: shouldWrap,
      );
    }
    String hangingIndentString;
    final String indentString = ' ' * indent;
    result.addAll(notIndented.map(
      (String line) {
        // Don't return any lines with just whitespace on them.
        if (line.isEmpty) {
          return '';
        }
        final String result = '$indentString${hangingIndentString ?? ''}$leadingWhitespace$line';
        hangingIndentString ??= ' ' * hangingIndent;
        return result;
      },
    ));
  }
  return result.join('\n');
}

// Used to represent a run of ANSI control sequences next to a visible
// character.
class _AnsiRun {
  _AnsiRun(this.original, this.character);

  String original;
  String character;
}

/// Wraps a block of text into lines no longer than [columnWidth], starting at the
/// [start] column, and returning the result as a list of strings.
///
/// Tries to split at whitespace, but if that's not good enough to keep it
/// under the limit, then splits in the middle of a word. Preserves embedded
/// newlines, but not indentation (it trims whitespace from each line).
///
/// If [columnWidth] is not specified, then the column width will be the width of the
/// terminal window by default. If the stdout is not a terminal window, then the
/// default will be [outputPreferences.wrapColumn].
///
/// If [outputPreferences.wrapText] is false, then the text will be returned
/// simply split at the newlines, but not wrapped. If [shouldWrap] is specified,
/// then it overrides the [outputPreferences.wrapText] setting.
List<String> _wrapTextAsLines(String text, { int start = 0, int columnWidth, @required bool shouldWrap }) {
  if (text == null || text.isEmpty) {
    return <String>[''];
  }
  assert(columnWidth != null);
  assert(columnWidth >= 0);
  assert(start >= 0);
  shouldWrap ??= globals.outputPreferences.wrapText;

  /// Returns true if the code unit at [index] in [text] is a whitespace
  /// character.
  ///
  /// Based on: https://en.wikipedia.org/wiki/Whitespace_character#Unicode
  bool isWhitespace(_AnsiRun run) {
    final int rune = run.character.isNotEmpty ? run.character.codeUnitAt(0) : 0x0;
    return rune >= 0x0009 && rune <= 0x000D ||
        rune == 0x0020 ||
        rune == 0x0085 ||
        rune == 0x1680 ||
        rune == 0x180E ||
        rune >= 0x2000 && rune <= 0x200A ||
        rune == 0x2028 ||
        rune == 0x2029 ||
        rune == 0x202F ||
        rune == 0x205F ||
        rune == 0x3000 ||
        rune == 0xFEFF;
  }

  // Splits a string so that the resulting list has the same number of elements
  // as there are visible characters in the string, but elements may include one
  // or more adjacent ANSI sequences. Joining the list elements again will
  // reconstitute the original string. This is useful for manipulating "visible"
  // characters in the presence of ANSI control codes.
  List<_AnsiRun> splitWithCodes(String input) {
    final RegExp characterOrCode = RegExp('(\u001b\\[[0-9;]*m|.)', multiLine: true);
    List<_AnsiRun> result = <_AnsiRun>[];
    final StringBuffer current = StringBuffer();
    for (final Match match in characterOrCode.allMatches(input)) {
      current.write(match[0]);
      if (match[0].length < 4) {
        // This is a regular character, write it out.
        result.add(_AnsiRun(current.toString(), match[0]));
        current.clear();
      }
    }
    // If there's something accumulated, then it must be an ANSI sequence, so
    // add it to the end of the last entry so that we don't lose it.
    if (current.isNotEmpty) {
      if (result.isNotEmpty) {
        result.last.original += current.toString();
      } else {
        // If there is nothing in the string besides control codes, then just
        // return them as the only entry.
        result = <_AnsiRun>[_AnsiRun(current.toString(), '')];
      }
    }
    return result;
  }

  String joinRun(List<_AnsiRun> list, int start, [ int end ]) {
    return list.sublist(start, end).map<String>((_AnsiRun run) => run.original).join().trim();
  }

  final List<String> result = <String>[];
  final int effectiveLength = max(columnWidth - start, kMinColumnWidth);
  for (final String line in text.split('\n')) {
    // If the line is short enough, even with ANSI codes, then we can just add
    // add it and move on.
    if (line.length <= effectiveLength || !shouldWrap) {
      result.add(line);
      continue;
    }
    final List<_AnsiRun> splitLine = splitWithCodes(line);
    if (splitLine.length <= effectiveLength) {
      result.add(line);
      continue;
    }

    int currentLineStart = 0;
    int lastWhitespace;
    // Find the start of the current line.
    for (int index = 0; index < splitLine.length; ++index) {
      if (splitLine[index].character.isNotEmpty && isWhitespace(splitLine[index])) {
        lastWhitespace = index;
      }

      if (index - currentLineStart >= effectiveLength) {
        // Back up to the last whitespace, unless there wasn't any, in which
        // case we just split where we are.
        if (lastWhitespace != null) {
          index = lastWhitespace;
        }

        result.add(joinRun(splitLine, currentLineStart, index));

        // Skip any intervening whitespace.
        while (index < splitLine.length && isWhitespace(splitLine[index])) {
          index++;
        }

        currentLineStart = index;
        lastWhitespace = null;
      }
    }
    result.add(joinRun(splitLine, currentLineStart));
  }
  return result;
}
