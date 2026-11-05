// The list order of a pane (02 §2.2 block E): folders and drives first whatever the column, the
// sort remembered on this device for each pane. Written here rather than reusing the copy's
// `_sortList`, which drops drives when sorting by type or size and sorts "ascending" dates and
// sizes largest first.
import '../../consts.dart';
import '../../models/file_model.dart';
import '../../models/platform_model.dart';
import 'pane.dart';

const kDefaultFileSort = (field: FileSortField.name, ascending: true);

/// [entries] in [sort] order: folders (links to folders too) and drives, then files. Names
/// compare without case; ties go by name.
List<Entry> sortEntries(List<Entry> entries, FileSort sort) {
  int byName(Entry a, Entry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  int byField(Entry a, Entry b) {
    final c = switch (sort.field) {
      FileSortField.name => 0,
      FileSortField.modified => a.modifiedTime.compareTo(b.modifiedTime),
      FileSortField.type => _extension(a).compareTo(_extension(b)),
      FileSortField.size => a.size.compareTo(b.size),
    };
    return c != 0 ? c : byName(a, b);
  }

  int compare(Entry a, Entry b) {
    final folderA = !a.isFile, folderB = !b.isFile;
    if (folderA != folderB) return folderA ? -1 : 1;
    // Folders have no size or type of their own.
    final c = folderA &&
            (sort.field == FileSortField.size ||
                sort.field == FileSortField.type)
        ? byName(a, b)
        : byField(a, b);
    return sort.ascending ? c : -c;
  }

  return [...entries]..sort(compare);
}

String _extension(Entry e) {
  final dot = e.name.lastIndexOf('.');
  return dot <= 0 ? '' : e.name.substring(dot + 1).toLowerCase();
}

/// The sort saved for the local or the remote pane; [kDefaultFileSort] when none is.
FileSort loadFileSort({required bool isLocal}) {
  final v = bind
      .mainGetLocalOption(
          key: isLocal ? kLeapgateFtSortLocal : kLeapgateFtSortRemote)
      .split(':');
  final field = FileSortField.values.where((f) => f.name == v.first);
  if (field.isEmpty || v.length != 2) return kDefaultFileSort;
  return (field: field.single, ascending: v.last != 'desc');
}

Future<void> saveFileSort(FileSort sort, {required bool isLocal}) =>
    bind.mainSetLocalOption(
        key: isLocal ? kLeapgateFtSortLocal : kLeapgateFtSortRemote,
        value: '${sort.field.name}:${sort.ascending ? 'asc' : 'desc'}');
