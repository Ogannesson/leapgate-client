import 'dart:async';
import 'dart:io';

import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/install_page.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart' as win32;

import 'exit_fakes.dart';
import 'fakes.dart';

/// Drives and folders as the checks see them. The paths here are made up.
class FakeInstallSystem implements InstallSystem {
  @override
  String defaultPath = r'C:\Program Files\Leapgate';

  @override
  String get appName => 'Leapgate';

  @override
  String programFolder = r'C:\Apps\Leap gate\leapgate-0.4.0';

  /// Drive letters that are not fixed disks, with their `GetDriveTypeW` answer.
  final drives = <String, int>{
    'Z': win32.DRIVE_REMOTE,
    'E': win32.DRIVE_REMOVABLE
  };
  final roots = <String>[];

  /// Folders that have something in them.
  final full = <String>{};

  @override
  int driveType(String root) {
    roots.add(root);
    return drives[root[0]] ?? win32.DRIVE_FIXED;
  }

  /// Drive letters made with `subst`.
  final substs = <String>{};

  @override
  bool isSubst(String root) => substs.contains(root[0]);

  /// Folders that are junctions or symbolic links, and where they lead.
  final links = <String, String>{};

  @override
  String resolveFolder(String folder) => links[folder] ?? folder;

  @override
  bool hasFiles(String folder) => full.contains(folder);
}

void main() {
  test('driveRoot: a drive letter path gives its root, a UNC path none', () {
    expect(driveRoot(r'd:\Apps\Leapgate'), r'D:\');
    expect(driveRoot(r'\\fileserver\share\Leapgate'), isNull);
    expect(driveRoot(r'\\?\C:\Apps\Leapgate'), isNull);
    expect(driveRoot('Leapgate'), isNull);
  });

  test(
      'isInFolder: the folder itself or below it, case and trailing separators aside',
      () {
    const program = r'C:\Apps\Local\leapgate';
    expect(isInFolder(r'C:\Apps\Local\Leapgate', program), isTrue);
    expect(isInFolder(r'c:\apps\local\leapgate\', program), isTrue);
    expect(isInFolder(r'C:\Apps\Local\leapgate\sub\Leapgate', '$program\\'),
        isTrue);
    expect(isInFolder(r'C:\Apps\Local\leapgate2\Leapgate', program), isFalse);
    expect(isInFolder(r'C:\Apps\Leapgate', program), isFalse);
  });

  group('checkInstallLocation (R3-Q24)', () {
    late FakeInstallSystem system;
    setUp(() => system = FakeInstallSystem());

    test('a network drive, a removable disk and a UNC path are not local disks',
        () {
      expect(checkInstallLocation(r'Z:\Leapgate', system),
          InstallLocationIssue.notLocalDisk);
      expect(checkInstallLocation(r'E:\Leapgate', system),
          InstallLocationIssue.notLocalDisk);
      system.roots.clear();
      expect(checkInstallLocation(r'\\fileserver\share\Leapgate', system),
          InstallLocationIssue.notLocalDisk);
      expect(system.roots, isEmpty);
    });

    test('a subst drive is not local: the elevated installer does not see it',
        () {
      system.substs.add('S');
      expect(checkInstallLocation(r'S:\Apps\Leapgate', system),
          InstallLocationIssue.notLocalDisk);
    });

    test(
        '"%", then the program folder, then a folder with files; the first one shows',
        () {
      expect(checkInstallLocation(r'D:\100%\Leapgate', system),
          InstallLocationIssue.percent);
      // The network drive comes before "%".
      expect(checkInstallLocation(r'Z:\100%\Leapgate', system),
          InstallLocationIssue.notLocalDisk);
      // "%" comes before the program folder.
      expect(
          checkInstallLocation(
              r'C:\Apps\Leap gate\leapgate-0.4.0\100%\Leapgate', system),
          InstallLocationIssue.percent);
      expect(
          checkInstallLocation(
              r'C:\APPS\Leap gate\leapgate-0.4.0\Leapgate', system),
          InstallLocationIssue.insideProgram);
      // The program folder comes before a folder with files.
      system.full.add(r'C:\Apps\Leap gate\leapgate-0.4.0\Leapgate');
      expect(
          checkInstallLocation(
              r'C:\Apps\Leap gate\leapgate-0.4.0\Leapgate', system),
          InstallLocationIssue.insideProgram);
      system.full.add(r'D:\Tools\Leapgate');
      expect(checkInstallLocation(r'D:\Tools\Leapgate', system),
          InstallLocationIssue.notEmpty);
      expect(checkInstallLocation(r'D:\Apps\Leapgate', system), isNull);
    });

    test('a junction to the program folder is the program folder', () {
      system.links[r'D:\Shortcut'] = r'C:\Apps\Leap gate\leapgate-0.4.0';
      expect(checkInstallLocation(r'D:\Shortcut\Leapgate', system),
          InstallLocationIssue.insideProgram);
    });
  });

  test('on Windows the system answers for C:\\: a fixed disk, not subst', () {
    const system = WindowsInstallSystem();
    expect(system.driveType(r'C:\'), win32.DRIVE_FIXED);
    expect(system.isSubst(r'C:\'), isFalse);
  }, skip: !Platform.isWindows);

  group('InstallPageModel', () {
    late FakeInstallSystem system;
    late FakeLeapgate lg;
    setUp(() {
      lg = installFakes().lg;
      system = FakeInstallSystem();
      installSystem = system;
      addTearDown(() => installSystem = const WindowsInstallSystem());
    });

    test(
        'opens on the default location with both shortcuts, the printer as asked',
        () {
      final status = LocalStatusModel();
      final page = InstallPageModel(status);
      expect(page.path, r'C:\Program Files\Leapgate');
      expect(page.issue, isNull);
      expect((page.startMenu, page.desktopShortcut, page.printer),
          (true, true, false));
      expect(InstallPageModel(status, printer: true).printer, isTrue);
    });

    test(
        '"修改" starts at the parent; the picked folder gets the app name and is checked',
        () {
      final page = InstallPageModel(LocalStatusModel());
      expect(page.pickerStart, r'C:\Program Files');

      page.choose(r'Z:\');
      expect(page.path, r'Z:\Leapgate');
      expect(page.issue, InstallLocationIssue.notLocalDisk);
      expect(page.blocked, isTrue);

      system.full.add(r'D:\Tools\Leapgate');
      page.choose(r'D:\Tools');
      expect(page.issue, InstallLocationIssue.notEmpty);
      expect(page.blocked, isFalse);
      expect(page.pickerStart, r'D:\Tools');
    });

    test('"安装" installs; its failure shows until the location changes',
        () async {
      lg.installAnswer = Completer();
      final status = LocalStatusModel();
      final page = InstallPageModel(status)..choose(r'D:\Apps');
      final done = page.install();
      expect(status.installing, isTrue);
      lg.installAnswer.complete('{"result":"uac_denied","text":""}');
      await done;
      expect(lg.installs, ['install']);
      expect(page.failure?.uacDenied, isTrue);

      page.choose(r'D:\Tools');
      expect(page.failure, isNull);
      // Nor does a page opened after it show it.
      expect(InstallPageModel(status).failure, isNull);
    });

    test('sessions end: a session tab or a session into this device', () {
      final status = LocalStatusModel();
      final page = InstallPageModel(status);
      var changes = 0;
      page.sessionsChanges.addListener(() => changes++);
      expect(page.sessionsEnd, isFalse);

      status
        ..incoming = const IncomingSessions(1, controlled: false)
        ..notifyListeners();
      expect(page.sessionsEnd, isTrue);
      expect(changes, 1);

      status.incoming = IncomingSessions.none;
      appCore.sessions.open('100200300', ConnType.defaultConn);
      expect(page.sessionsEnd, isTrue);
      expect(changes, 2);
    });
  });

  test('sessions end: an exit node in use', () {
    installExitFakes();
    installSystem = FakeInstallSystem();
    addTearDown(() => installSystem = const WindowsInstallSystem());
    final page = InstallPageModel(LocalStatusModel());
    var changes = 0;
    page.sessionsChanges.addListener(() => changes++);
    expect(page.sessionsEnd, isFalse);

    appCore.exitNodes.use('100200300');
    expect(appCore.backgroundCount, 1);
    expect(page.sessionsEnd, isTrue);
    expect(changes, greaterThan(0));
  });
}
