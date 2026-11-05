import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/file_transfer/errors.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/l10n/app_localizations_zh.dart';
import 'package:leapgate_ui/pages/files/breadcrumb.dart';
import 'package:leapgate_ui/pages/files/file_list.dart';
import 'package:leapgate_ui/pages/files/file_view.dart';
import 'package:leapgate_ui/pages/files/formats.dart';
import 'package:leapgate_ui/pages/files/pane.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_tooltip.dart';

import 'file_transfer_fakes.dart';
import 'session_fakes.dart';

// The two panes of the file transfer view, one test per group of 02 §2.2 "P7 桌面要画的状态"
// that is about them (2, 4 to 10), plus the keys and the formats. The model is the step 0 fake.

Entry _e(
  String name, {
  int type = 4,
  int size = 0,
  String dir = r'C:\Users\u\Documents',
  bool hidden = false,
  String? path,
}) {
  return Entry()
    ..name = name
    ..entryType = type
    ..size = size
    ..isHidden = hidden
    ..modifiedTime = 1761631500
    ..path = path ?? '$dir\\$name';
}

const _dir = 0, _dirLink = 2, _drive = 3, _fileLink = 5;

FakeFilePane _local() => FakeFilePane()
  ..path = r'C:\Users\u\Documents'
  ..entries = [
    _e('照片', type: _dir),
    _e('年度报告.docx', size: 2516582),
    _e('预算.xlsx', size: 88576),
  ];

FakeFilePane _remote() => FakeFilePane(isLocal: false)
  ..path = r'D:\备份'
  ..entries = [
    _e('旧照片', type: _dir, dir: r'D:\备份'),
    _e('说明.txt', size: 4096, dir: r'D:\备份'),
  ];

/// A remote pane whose drives come when the test says.
class _SlowDrives extends FakeFilePane {
  _SlowDrives() : super(isLocal: false);

  final read = Completer<List<Entry>>();

  @override
  Future<List<Entry>> drives() => read.future;
}

class _View {
  _View(this.ffi, this.model, this.disconnects);

  final FFI ffi;
  final FakeFileTransferModel model;
  final List<int> disconnects;
}

Future<_View> _pump(
  WidgetTester tester, {
  FakeFilePane? local,
  FakeFilePane? remote,
  bool connected = true,
  bool active = true,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ffi = FFI('100200300', ConnType.fileTransfer);
  ffi.ffiModel.pi
    ..platform = 'Windows'
    ..hostname = 'den-pc';
  if (connected) ffi.connection.onPeerInfo();
  final model = FakeFileTransferModel(
    local: local ?? _local(),
    remote: remote ?? _remote(),
  );
  final v = _View(ffi, model, <int>[]);
  await tester.pumpWidget(_app(v, active: active));
  await tester.pump();
  return v;
}

Widget _app(_View v, {required bool active}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
  home: Scaffold(
    body: FileView(
      ffi: v.ffi,
      model: v.model,
      active: active,
      lastView: true,
      viewSwitch: const Text('视图切换'),
      route: const Text('直连'),
      onDisconnect: () => v.disconnects.add(1),
    ),
  ),
);

/// The row of [name], the widget that has its semantics.
Finder _row(String name) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.label == name &&
      w.properties.selected != null,
);

Finder _inPane(String paneTitle, Finder f) => find.descendant(
  of: find.ancestor(
    of: find.text(paneTitle),
    matching: find.byType(FilePaneView),
  ),
  matching: f,
);

/// A row of the open menu.
Finder _menuItem(String label) =>
    find.byWidgetPredicate((w) => w is LgMenuItem && w.label == label);

Finder _tip(String text) =>
    find.byWidgetPredicate((w) => w is LgTooltip && w.message == text);

Future<void> _click(
  WidgetTester tester,
  Finder f, {
  int buttons = kPrimaryMouseButton,
}) async {
  final g = await tester.startGesture(
    tester.getCenter(f),
    kind: PointerDeviceKind.mouse,
    buttons: buttons,
  );
  await g.up();
  await tester.pump();
  // A menu opens in the frame after.
  await tester.pump();
}

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  List<LogicalKeyboardKey> held = const [],
}) async {
  for (final k in held) {
    await tester.sendKeyDownEvent(k);
  }
  await tester.sendKeyEvent(key);
  for (final k in held.reversed) {
    await tester.sendKeyUpEvent(k);
  }
  await tester.pump();
}

/// A message to `desktop_drop` as its Windows plugin sends it.
Future<void> _systemDrag(
  WidgetTester tester,
  String method,
  Object args,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'desktop_drop',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
  await tester.pump();
}

List<double> _at(Offset o) => [o.dx, o.dy];

void main() {
  late AppFakes fakes;
  setUp(() => fakes = installAppFakes());

  group('formats', () {
    final l10n = AppLocalizationsZh();
    test('sizes: 1024-based, three significant digits, bytes under 1 KB', () {
      expect(formatFileSize(l10n, 0), '0 字节');
      expect(formatFileSize(l10n, 1023), '1023 字节');
      expect(formatFileSize(l10n, 1024), '1 KB');
      expect(formatFileSize(l10n, 512 * 1024), '512 KB');
      expect(formatFileSize(l10n, 88576), '86.5 KB');
      expect(formatFileSize(l10n, 2516582), '2.4 MB');
      expect(
        formatFileSize(l10n, (1.32 * 1024 * 1024 * 1024).round()),
        '1.32 GB',
      );
      // 1000 KB would need four digits.
      expect(formatFileSize(l10n, 1000 * 1024), '0.977 MB');
    });

    test('types, partial transfers and folder names', () {
      final names = {'a.mp4.download', 'a.mp4.digest', 'b.download'};
      expect(fileTypeText(l10n, _e('年度报告.docx')), 'DOCX 文件');
      expect(fileTypeText(l10n, _e('README')), '文件');
      expect(fileTypeText(l10n, _e('x', type: _dir)), '文件夹');
      expect(fileTypeText(l10n, _e('C:', type: _drive)), '驱动器');
      expect(fileTypeText(l10n, _e('l', type: _fileLink)), '符号链接');
      expect(isPartialTransfer(_e('a.mp4.download'), names), isTrue);
      expect(isPartialTransfer(_e('a.mp4.digest'), names), isTrue);
      expect(isPartialTransfer(_e('b.download'), names), isFalse);
      expect(folderName(l10n, r'C:\', true), 'C:');
      expect(folderName(l10n, r'D:\备份\照片', true), '照片');
      expect(folderName(l10n, '/', true), '此电脑');
      expect(folderName(l10n, '/home/u', false), 'u');
    });

    test('the system date format has the date and the time', () {
      final text = formatFileDate(_e('x'));
      expect(text, contains('2025'));
      expect(text, isNot(contains(':00:00')));
    });

    test('crumbs of Windows, POSIX and "此电脑"; the middle goes first', () {
      expect(crumbsOf('/', true, '此电脑').map((c) => c.label), ['此电脑']);
      expect(crumbsOf(r'C:\Users\u', true, '此电脑'), [
        (label: '此电脑', path: '/'),
        (label: 'C:', path: r'C:\'),
        (label: 'Users', path: r'C:\Users'),
        (label: 'u', path: r'C:\Users\u'),
      ]);
      expect(crumbsOf('/home/u', false, '此电脑').map((c) => c.path), [
        '/',
        '/home',
        '/home/u',
      ]);
      expect(visibleCrumbs([50, 50, 50, 50, 50, 50], 20, 1000), [
        0,
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(visibleCrumbs([50, 50, 50, 50, 50, 50], 20, 230), [0, 1, 4, 5]);
      // Fewer than four segments: the root, "…" and the current one.
      expect(visibleCrumbs([50, 200, 200], 20, 300), [0, 2]);
      expect(
        openErrorText(
          l10n,
          r'D:\x',
          const FtError(FtReason.other, text: 'Wrong id.'),
          true,
        ),
        '无法打开“x”：Wrong id。',
      );
    });
  });

  testWidgets(
    'default: headers, rows, the selection and the title bar (group 2)',
    (tester) async {
      final v = await _pump(tester);
      expect(find.text('本机'), findsOneWidget);
      expect(find.text('远程设备'), findsOneWidget);
      expect(find.text('den-pc（Windows）'), findsOneWidget);
      expect(find.text('视图切换'), findsOneWidget);
      expect(find.text('直连'), findsOneWidget);
      expect(find.text('DOCX 文件'), findsOneWidget);
      expect(find.text('2.4 MB'), findsOneWidget);
      expect(find.text('3 个项目'), findsOneWidget);
      expect(find.text('2 个项目'), findsOneWidget);

      await tester.tap(find.text('断开'));
      expect(v.disconnects, [1]);
    },
  );

  testWidgets(
    'the connection panel covers the panes until connected (groups 1, 13)',
    (tester) async {
      final v = await _pump(tester, connected: false);
      expect(find.byType(ModalBarrier), findsWidgets);
      expect(find.textContaining('正在连接'), findsWidgets);
      v.ffi.connection.onPeerInfo();
      await tester.pump();
      expect(find.textContaining('正在连接'), findsNothing);
    },
  );

  group('list states (group 4)', () {
    testWidgets('"正在读取…" only after 0.5 s; another folder dims the old rows', (
      tester,
    ) async {
      final v = await _pump(tester);
      final remote = v.model.remote;
      remote.reading = (path: r'D:\别处', since: DateTime.now());
      remote.notifyListeners();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('正在读取…'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('正在读取…'), findsOneWidget);
      final dim = tester.widget<Opacity>(
        find.ancestor(of: _row('说明.txt'), matching: find.byType(Opacity)).last,
      );
      expect(dim.opacity, lessThan(1));

      remote.reading = null;
      remote.notifyListeners();
      await tester.pump();
      expect(find.text('正在读取…'), findsNothing);
    });

    testWidgets(
      'a folder that did not open: the banner, closed with its button',
      (tester) async {
        final v = await _pump(tester);
        v.model.remote
          ..openError = (
            path: r'D:\备份\私密',
            error: const FtError(FtReason.permissionDenied),
          )
          ..notifyListeners();
        await tester.pump();
        expect(find.text('无法打开“私密”：没有访问权限。'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('关闭'));
        await tester.pump();
        expect(v.model.remote.calls, contains('dismissOpenError'));
        expect(find.text('无法打开“私密”：没有访问权限。'), findsNothing);
      },
    );

    testWidgets('the first folder did not open: "转到主文件夹" and "重试"', (
      tester,
    ) async {
      final remote = FakeFilePane(isLocal: false)
        ..openError = (path: r'D:\丢了', error: const FtError(FtReason.notFound));
      await _pump(tester, remote: remote);
      expect(find.text(r'未找到“D:\丢了”。'), findsOneWidget);
      await tester.tap(find.text('转到主文件夹'));
      await tester.tap(find.text('重试'));
      expect(remote.calls, ['goHome', r'openDirectory:D:\丢了']);
    });

    testWidgets('an empty folder, and a search without a match', (
      tester,
    ) async {
      final remote = FakeFilePane(isLocal: false)..path = r'D:\空';
      await _pump(tester, remote: remote);
      expect(find.text('此文件夹为空'), findsOneWidget);

      // Not case-sensitive (02 §2.2 block D).
      await tester.enterText(_inPane('本机', find.byType(EditableText)), 'DOCX');
      await tester.pump();
      expect(_row('年度报告.docx'), findsOneWidget);
      expect(_row('预算.xlsx'), findsNothing);
      expect(find.text('1 个项目'), findsOneWidget);
      await tester.enterText(_inPane('本机', find.byType(EditableText)), 'zzz');
      await tester.pump();
      expect(find.text('未找到匹配的项目'), findsOneWidget);
    });
  });

  group('the path (group 5)', () {
    testWidgets('"此电脑": the drives; the root drop-down reads them', (
      tester,
    ) async {
      final remote = _SlowDrives()
        ..path = '/'
        ..entries = [
          _e('C:', type: _drive, path: r'C:\'),
          _e('D:', type: _drive, path: r'D:\'),
        ];
      final v = await _pump(tester, remote: remote);
      // The local pane can't send to "此电脑".
      expect(_inPane('远程设备', find.text('驱动器')), findsNWidgets(2));
      await _click(tester, _row('年度报告.docx'));
      await tester.tap(find.text('上传'));
      expect(v.model.local.calls, isEmpty);
      expect(_tip('目标位置不能是“此电脑”'), findsOneWidget);

      await tester.tap(
        _inPane(
          '远程设备',
          find.byWidgetPredicate((w) => w is LgIconButton && w.label == '此电脑'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_menuItem('正在读取…'), findsOneWidget);
      remote.read.complete([_e('C:', type: _drive, path: r'C:\')]);
      await tester.pump();
      expect(_menuItem('正在读取…'), findsNothing);
      await tester.tap(_menuItem('C:'));
      await tester.pump();
      expect(v.model.remote.calls, contains(r'openDirectory:C:\'));
    });

    testWidgets(
      'a Linux device starts at "/"; a long path leaves out the middle',
      (tester) async {
        final remote = FakeFilePane(isLocal: false, isWindows: false)
          ..path = '/home/u';
        final local = _local()
          ..path = r'C:\Users\u\Documents\工作\项目\二零二六年\十月\会议纪要\附件\最终版';
        await _pump(
          tester,
          local: local,
          remote: remote,
          size: const Size(960, 600),
        );
        expect(_inPane('远程设备', find.text('/')), findsOneWidget);
        expect(_inPane('远程设备', find.text('home')), findsOneWidget);
        expect(_inPane('本机', find.text('…')), findsOneWidget);
        expect(_inPane('本机', find.text('最终版')), findsOneWidget);
        expect(_inPane('本机', find.text('C:')), findsOneWidget);
      },
    );

    testWidgets(
      'Ctrl+L edits the path; one that is not there shows under the field',
      (tester) async {
        final v = await _pump(tester);
        final remote = v.model.remote
          ..openResult = const FtError(FtReason.notFound);
        await _click(tester, _row('说明.txt'));
        await _key(
          tester,
          LogicalKeyboardKey.keyL,
          held: [LogicalKeyboardKey.controlLeft],
        );
        await tester.pump();
        final field = _inPane('远程设备', find.byType(EditableText)).first;
        expect(tester.widget<EditableText>(field).controller.text, r'D:\备份');
        await tester.enterText(field, r'D:\没有');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(remote.calls, contains(r'openDirectory:D:\没有'));
        expect(find.text(r'未找到“D:\没有”。'), findsOneWidget);
      },
    );
  });

  testWidgets(
    'entries: hidden ones see-through, links, partial transfers (group 6)',
    (tester) async {
      final remote = FakeFilePane(isLocal: false)
        ..path = r'D:\备份'
        ..entries = [
          _e('.secret', hidden: true, dir: r'D:\备份'),
          _e('快捷', type: _dirLink, dir: r'D:\备份'),
          _e('链接.txt', type: _fileLink, size: 10, dir: r'D:\备份'),
          _e('v.mp4.download', size: 2048, dir: r'D:\备份'),
          _e('v.mp4.digest', size: 64, dir: r'D:\备份'),
        ];
      await _pump(tester, remote: remote);
      final hidden = tester.widget<Opacity>(
        find
            .descendant(of: _row('.secret'), matching: find.byType(Opacity))
            .first,
      );
      expect(hidden.opacity, 0.5);
      expect(find.text('符号链接'), findsNWidgets(2));
      expect(find.text('10 字节'), findsNothing);
      expect(find.text('未完成的传输'), findsNWidgets(2));
      expect(find.text('64 字节'), findsOneWidget);
    },
  );

  testWidgets(
    'selection: click, Ctrl, Shift, Ctrl+A and the status line (group 7)',
    (tester) async {
      final v = await _pump(tester);
      final local = v.model.local;
      await _click(tester, _row('年度报告.docx'));
      expect(local.selection.map((e) => e.name), ['年度报告.docx']);
      expect(find.text('已选择 1 个项目，2.4 MB'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await _click(tester, _row('照片'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(local.selection.map((e) => e.name), ['照片', '年度报告.docx']);
      expect(find.text('已选择 2 个项目（含 1 个文件夹）'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await _click(tester, _row('照片'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(local.selection.map((e) => e.name), ['年度报告.docx']);

      // The button sends to the remote pane's folder and says which.
      await tester.tap(find.text('上传'));
      expect(local.calls, ['transfer:年度报告.docx']);
      expect(_tip('上传到“备份”'), findsOneWidget);

      await _key(
        tester,
        LogicalKeyboardKey.keyA,
        held: [LogicalKeyboardKey.controlLeft],
      );
      expect(local.selection, hasLength(3));
    },
  );

  testWidgets('"⋯": hidden items, select all, sort (group 8)', (tester) async {
    final v = await _pump(tester);
    await tester.tap(_inPane('本机', find.bySemanticsLabel('更多')));
    await tester.pump();
    expect(find.text('显示隐藏的项目'), findsOneWidget);
    expect(find.text('取消选择'), findsOneWidget);
    await tester.tap(find.text('显示隐藏的项目'));
    await tester.pump();
    expect(v.model.local.calls, contains('setShowHidden:true'));
  });

  group('context menus (group 9)', () {
    testWidgets('a folder, a file, a drive and the blank', (tester) async {
      final v = await _pump(tester);
      await _click(tester, _row('照片'), buttons: kSecondaryMouseButton);
      for (final item in ['打开', '上传', '重命名', '删除', '复制路径']) {
        expect(find.text(item), findsWidgets, reason: item);
      }
      expect(find.text('F2'), findsOneWidget);
      await tester.tap(_menuItem('重命名'));
      await tester.pump();
      expect(v.model.local.calls, contains('rename:照片'));

      // The blank under the rows.
      final list = _inPane('本机', find.byType(ListView));
      await _click(tester, list, buttons: kSecondaryMouseButton);
      expect(find.text('新建文件夹'), findsWidgets);
      expect(find.text('Ctrl+Shift+N'), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);
    });

    testWidgets('several selected: "重命名" is greyed', (tester) async {
      final v = await _pump(tester);
      v.model.local.select(v.model.local.entries.sublist(1));
      await tester.pump();
      await _click(tester, _row('预算.xlsx'), buttons: kSecondaryMouseButton);
      await tester.tap(_menuItem('删除'));
      await tester.pump();
      expect(v.model.local.calls, ['delete:年度报告.docx,预算.xlsx']);

      await _click(tester, _row('预算.xlsx'), buttons: kSecondaryMouseButton);
      await tester.tap(_menuItem('重命名'), warnIfMissed: false);
      await tester.pump();
      expect(v.model.local.calls, ['delete:年度报告.docx,预算.xlsx']);
    });
  });

  group('drag and drop (group 10)', () {
    testWidgets(
      'from the system onto the remote pane, its folder row, not this device',
      (tester) async {
        final v = await _pump(tester);
        final folder = tester.getCenter(_row('旧照片'));
        final blank = tester.getCenter(_inPane('远程设备', find.byType(ListView)));
        final local = tester.getCenter(_row('预算.xlsx'));

        await _systemDrag(tester, 'entered', _at(blank));
        expect(find.text('上传到“备份”'), findsOneWidget);
        await _systemDrag(tester, 'updated', _at(folder));
        expect(find.text('上传到“旧照片”'), findsOneWidget);
        await _systemDrag(tester, 'updated', _at(local));
        expect(find.text('无法放到此处'), findsOneWidget);
        await _systemDrag(tester, 'updated', _at(folder));
        await _systemDrag(tester, 'performOperation', [r'C:\a.txt', r'C:\文件夹']);
        expect(v.model.uploads.single.paths, [r'C:\a.txt', r'C:\文件夹']);
        expect(v.model.uploads.single.to, r'D:\备份\旧照片');
        expect(find.text('上传到“旧照片”'), findsNothing);

        await _systemDrag(tester, 'entered', _at(local));
        await _systemDrag(tester, 'performOperation', [r'C:\b.txt']);
        expect(v.model.uploads, hasLength(1));
      },
    );

    testWidgets('from one pane onto a folder row of the other', (tester) async {
      final v = await _pump(tester);
      // The press selects the row it starts on.
      final g = await tester.startGesture(
        tester.getCenter(_row('预算.xlsx')),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.moveTo(tester.getCenter(_row('旧照片')));
      await tester.pump();
      expect(find.text('下载到“旧照片”'), findsNothing);
      expect(find.text('上传到“旧照片”'), findsOneWidget);
      await g.up();
      await tester.pump();
      expect(v.model.local.calls, [r'transfer:预算.xlsx>D:\备份\旧照片']);
    });

    testWidgets('back onto the pane it came from: not taken (no move)', (
      tester,
    ) async {
      final v = await _pump(tester);
      final g = await tester.startGesture(
        tester.getCenter(_row('预算.xlsx')),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(0, -20));
      await tester.pump();
      await g.moveTo(tester.getCenter(_row('照片')));
      await tester.pump();
      expect(find.text('无法放到此处'), findsOneWidget);
      expect(find.text('上传到“照片”'), findsNothing);
      await g.up();
      await tester.pump();
      expect(v.model.local.calls, isEmpty);
      expect(find.text('无法放到此处'), findsNothing);
    });
  });

  group('double click and Enter', () {
    testWidgets('a file goes to the other pane\'s folder (R2-Q27)', (
      tester,
    ) async {
      final v = await _pump(tester);
      await _click(tester, _row('预算.xlsx'));
      await _click(tester, _row('预算.xlsx'));
      expect(v.model.local.calls, ['transfer:预算.xlsx']);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(v.model.local.calls, ['transfer:预算.xlsx', 'transfer:预算.xlsx']);
    });

    testWidgets('a folder opens', (tester) async {
      final v = await _pump(tester);
      await _click(tester, _row('旧照片'));
      await _click(tester, _row('旧照片'));
      expect(v.model.remote.calls, [r'openDirectory:D:\备份\旧照片']);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(v.model.remote.calls, [
        r'openDirectory:D:\备份\旧照片',
        r'openDirectory:D:\备份\旧照片',
      ]);
    });
  });

  group('keys', () {
    testWidgets(
      'arrows, Enter, Backspace, F5, Delete, F2, Tab, typing to jump',
      (tester) async {
        final v = await _pump(tester);
        final local = v.model.local..canGoBack = true;
        await _click(tester, _row('照片'));
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(local.selection.single.name, '年度报告.docx');
        await _key(
          tester,
          LogicalKeyboardKey.arrowDown,
          held: [LogicalKeyboardKey.shiftLeft],
        );
        expect(local.selection, hasLength(2));
        await _key(tester, LogicalKeyboardKey.delete);
        expect(local.calls, contains('delete:年度报告.docx,预算.xlsx'));
        await _key(tester, LogicalKeyboardKey.home);
        await _key(tester, LogicalKeyboardKey.enter);
        expect(local.calls, contains(r'openDirectory:C:\Users\u\Documents\照片'));
        await _key(tester, LogicalKeyboardKey.backspace);
        await _key(tester, LogicalKeyboardKey.f5);
        await _key(tester, LogicalKeyboardKey.f2);
        expect(local.calls, containsAll(['goBack', 'refresh', 'rename:照片']));

        await tester.sendKeyEvent(LogicalKeyboardKey.keyY, character: '预');
        await tester.pump();
        expect(local.selection.single.name, '预算.xlsx');

        // Tab to the remote pane: its keys act there.
        await _key(tester, LogicalKeyboardKey.tab);
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(v.model.remote.selection.single.name, '旧照片');
      },
    );

    testWidgets('Ctrl+Tab and Ctrl+F5 go on to the tabs and the window', (
      tester,
    ) async {
      final v = await _pump(tester);
      await _click(tester, _row('照片'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.tab), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.f5), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(v.model.local.calls, isEmpty);
      // Tab alone switches panes.
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.tab), isTrue);
    });

    testWidgets('a view that is not shown takes no keys; shown, it does', (
      tester,
    ) async {
      final v = await _pump(tester, active: false);
      await _click(tester, _row('照片'));
      await _key(tester, LogicalKeyboardKey.f5);
      expect(v.model.local.calls, isNot(contains('refresh')));

      await tester.pumpWidget(_app(v, active: true));
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.f5);
      expect(v.model.local.calls, contains('refresh'));
    });
  });

  testWidgets(
    'the narrow pane: breadcrumb and columns fit, the search empties the selection',
    (tester) async {
      fakes.bind.localOptions[kOptionFtColumns] = '400,400,400';
      // The divider as far left as it goes.
      fakes.bind.localOptions[kOptionFtDivider] = '0.2';
      final v = await _pump(
        tester,
        local: _local()..path = r'C:\Users\u\Documents\一个名字非常非常非常非常非常非常长的文件夹',
        size: const Size(960, 600),
      );
      // An overflow would have failed the test; the name column keeps its room.
      final name = find
          .ancestor(of: find.text('年度报告.docx'), matching: find.byType(Expanded))
          .first;
      expect(
        tester.getSize(name).width,
        greaterThanOrEqualTo(kFileNameColumnMin),
      );
      // A long current folder leaves room for the root and "…" only, and is shortened.
      expect(_inPane('本机', find.text('…')), findsOneWidget);
      expect(_inPane('本机', find.text('C:')), findsNothing);
      expect(_inPane('本机', find.text('一个名字非常非常非常非常非常非常长的文件夹')), findsOneWidget);

      await _click(tester, _row('年度报告.docx'));
      expect(v.model.local.selection, hasLength(1));
      await tester.tap(_inPane('本机', find.bySemanticsLabel('搜索当前文件夹')));
      await tester.pump();
      await tester.pump();
      await tester.enterText(_inPane('本机', find.byType(EditableText)), '预');
      await tester.pump();
      expect(v.model.local.selection, isEmpty);
    },
  );

  testWidgets('the divider is remembered on this device', (tester) async {
    await _pump(tester);
    final divider = find.byWidgetPredicate(
      (w) => w is SizedBox && w.width == kFileDividerWidth,
    );
    await tester.drag(divider, const Offset(-128, 0));
    await tester.pump();
    expect(fakes.bind.localOptions[kOptionFtDivider], isNotEmpty);
    expect(
      double.parse(fakes.bind.localOptions[kOptionFtDivider]!),
      lessThan(0.5),
    );
  });
}
