// The install page (13 §4, M9a, `LEAPGATE.md` §10.18): where to install, the three options,
// whether the location can be used (R3-Q24) and whether installing ends sessions. Installing
// itself is `LocalStatusModel.install` (M8-1), which the page only starts.
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

import '../common.dart' as common show appName;
import '../models/platform_model.dart';
import 'app_core.dart';
import 'local_status.dart';

/// What the install page hands to the installer (`install_me`'s `startmenu`, `desktopicon`,
/// `printer`).
typedef InstallOptions = ({bool startMenu, bool desktopShortcut, bool printer});

/// What is wrong with an install location (13 §4.2 block A), in the order the page shows the
/// first: the first three keep "安装" greyed, [notEmpty] only warns.
enum InstallLocationIssue { notLocalDisk, percent, insideProgram, notEmpty }

/// What the location checks read from the system; tests set their own [installSystem].
abstract interface class InstallSystem {
  /// Upstream `install_install_path`: `%ProgramFiles%\Leapgate` while nothing is installed.
  String get defaultPath;

  /// The folder name added to the one the user picks.
  String get appName;

  /// The folder the running leapgate.exe is in; for the portable single file the folder it was
  /// unpacked to (13 §4.2 block A).
  String get programFolder;

  /// `GetDriveTypeW` of [root] ("D:\").
  int driveType(String root);

  /// [folder] exists and has something in it.
  bool hasFiles(String folder);
}

class WindowsInstallSystem implements InstallSystem {
  const WindowsInstallSystem();

  @override
  String get defaultPath => bind.installInstallPath();

  @override
  String get appName => common.appName;

  @override
  String get programFolder => p.dirname(Platform.resolvedExecutable);

  @override
  int driveType(String root) => using(
      (arena) => win32.GetDriveType(root.toNativeUtf16(allocator: arena)));

  @override
  bool hasFiles(String folder) {
    final dir = Directory(folder);
    try {
      return dir.existsSync() && dir.listSync().isNotEmpty;
    } on FileSystemException {
      // A folder it may not read gets no warning; the installer reports what it can't do.
      return false;
    }
  }
}

InstallSystem installSystem = const WindowsInstallSystem();

/// The volume root of a drive-letter path ("D:\"); null for a UNC path (`\\server\share`,
/// `\\?\…`) and anything else, which counts as a network location.
String? driveRoot(String path) {
  final drive = RegExp(r'^([A-Za-z]):[\\/]').firstMatch(path);
  return drive == null ? null : '${drive[1]!.toUpperCase()}:\\';
}

/// [path] is [folder] or in it, case and trailing separators aside.
bool isInFolder(String path, String folder) {
  String key(String s) =>
      p.windows.normalize(s).toLowerCase().replaceFirst(RegExp(r'\\+$'), '');
  final inner = key(path);
  final outer = key(folder);
  return inner == outer || inner.startsWith('$outer\\');
}

/// The first of the four checks (R3-Q24) that [path] fails; null when it passes them all. Only
/// a fixed disk is local: a mapped network drive, a removable disk, a CD drive and a RAM disk
/// are not; `subst` drives are fixed, since they are on one.
InstallLocationIssue? checkInstallLocation(String path, InstallSystem system) {
  final root = driveRoot(path);
  if (root == null || system.driveType(root) != win32.DRIVE_FIXED) {
    return InstallLocationIssue.notLocalDisk;
  }
  if (path.contains('%')) return InstallLocationIssue.percent;
  if (isInFolder(path, system.programFolder)) {
    return InstallLocationIssue.insideProgram;
  }
  if (system.hasFiles(path)) return InstallLocationIssue.notEmpty;
  return null;
}

/// One opening of the install page. The busy and failed states are [status]'s
/// (`installing`, `installFailure`), so the page shows what the installer answered.
class InstallPageModel extends ChangeNotifier {
  /// [printer] is ticked when the page is opened from 远程打印 (R3-Q20).
  InstallPageModel(this.status, {this.printer = false})
      : path = installSystem.defaultPath {
    issue = checkInstallLocation(path, installSystem);
    _hiddenFailure = status.installFailure;
  }

  final LocalStatusModel status;

  /// The whole location: the folder picked plus [InstallSystem.appName].
  String path;
  InstallLocationIssue? issue;

  bool startMenu = true;
  bool desktopShortcut = true;
  bool printer;

  /// A failure from before this opening, or from before the location last changed: not shown
  /// (13 §4.2 block D: the line goes when the location is changed).
  InstallFailure? _hiddenFailure;

  /// For the hover text of [InstallLocationIssue.insideProgram].
  String get programFolder => installSystem.programFolder;

  /// "安装" is greyed: the location can't be used.
  bool get blocked => issue != null && issue != InstallLocationIssue.notEmpty;

  /// The last "安装" from this page failed: the line above the buttons.
  InstallFailure? get failure {
    final failure = status.installFailure;
    return failure == null ||
            identical(failure, _hiddenFailure) ||
            failure.card != InstallCard.install
        ? null
        : failure;
  }

  /// Where the folder picker opens: the location's parent, since the app name is added to what
  /// is picked (14 §1.2).
  String get pickerStart => p.windows.dirname(path);

  /// Something in use ends when the installer stops every Leapgate process (13 §4.2 block D):
  /// a session tab, an exit node or tunnel in use, a session into this device. Not
  /// `serviceAsksFirst`: it asks about the installed version only.
  bool get sessionsEnd =>
      appCore.sessions.devices.isNotEmpty ||
      appCore.backgroundCount > 0 ||
      status.incoming.total > 0;

  /// Notifies when [sessionsEnd] may have changed.
  late final Listenable sessionsChanges = Listenable.merge(
      [appCore.sessions, appCore.backgroundListenable, status]);

  /// The folder picker answered with [folder].
  void choose(String folder) {
    path = p.windows.join(folder, installSystem.appName);
    issue = checkInstallLocation(path, installSystem);
    _hiddenFailure = status.installFailure;
    notifyListeners();
  }

  void setStartMenu(bool value) {
    startMenu = value;
    notifyListeners();
  }

  void setDesktopShortcut(bool value) {
    desktopShortcut = value;
    notifyListeners();
  }

  void setPrinter(bool value) {
    printer = value;
    notifyListeners();
  }

  /// "安装". Returns on failure only; on success this process is ended.
  Future<void> install() =>
      status.install(InstallCard.install, path: path, options: (
        startMenu: startMenu,
        desktopShortcut: desktopShortcut,
        printer: printer,
      ));
}
