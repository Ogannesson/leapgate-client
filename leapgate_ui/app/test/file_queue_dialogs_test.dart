import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/file_transfer/errors.dart';
import 'package:flutter_hbb/leapgate/file_transfer/jobs.dart';
import 'package:flutter_hbb/leapgate/prompts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/files/file_dialogs.dart';
import 'package:leapgate_ui/pages/files/queue_panel.dart';
import 'package:leapgate_ui/shell/tab_overlays.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';

import 'file_transfer_fakes.dart';
import 'session_fakes.dart' show AppFakes, installAppFakes;

// The transfer queue (02 §2.2 block H) and the file transfer dialogs (blocks I and J, §3.1),
// against fake jobs and questions. Names and paths here are made up.

class _Jobs extends FakeFileJobs {
  void changed() => notifyListeners();
}

FileJobSummary _summary({
  int active = 0,
  int queued = 0,
  int waiting = 0,
  int failed = 0,
  int paused = 0,
  int finished = 0,
  double? progress,
}) => (
  active: active,
  queued: queued,
  waitingConfirm: waiting,
  failed: failed,
  paused: paused,
  interrupted: 0,
  finished: finished,
  progress: progress,
);

FileJobRow _row(
  int id,
  FileJobStatus status, {
  FileJobDirection direction = FileJobDirection.download,
  String name = '照片',
  int done = 0,
  int total = 0,
  int index = 0,
  int count = 0,
  double? speed,
  Duration? remaining,
  FtError? error,
  List<FileJobNote> notes = const [],
}) => FileJobRow(
  id: id,
  direction: direction,
  name: name,
  from: r'D:\备份\照片',
  to: direction == FileJobDirection.delete ? '' : r'C:\Users\u\Pictures',
  status: status,
  doneBytes: done,
  totalBytes: total,
  fileIndex: index,
  fileCount: count,
  bytesPerSecond: speed,
  remaining: remaining,
  error: error,
  notes: notes,
);

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
  home: Scaffold(body: child),
);

Future<void> _pumpQueue(
  WidgetTester tester,
  FileJobs jobs, {
  ConnectionModel? connection,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      Align(
        alignment: Alignment.bottomCenter,
        child: FileQueuePanel(jobs: jobs, connection: connection),
      ),
    ),
  );
}

Finder _rich(String text) => find.textContaining(text, findRichText: true);

/// A row's icon button by its name.
Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is LgIconButton && w.label == label);

void main() {
  late AppFakes fakes;
  setUp(() => fakes = installAppFakes());

  group('the queue panel (02 block H)', () {
    testWidgets('no jobs: the summary alone, nothing to expand', (
      tester,
    ) async {
      await _pumpQueue(tester, _Jobs());
      expect(find.text('传输'), findsOneWidget);
      expect(_rich('暂无传输任务'), findsOneWidget);
      expect(find.text('展开'), findsNothing);
      expect(find.text('收起'), findsNothing);
    });

    testWidgets('the summary counts, colours aside, and the total progress', (
      tester,
    ) async {
      final jobs = _Jobs()
        ..rows = [
          _row(1, FileJobStatus.inProgress, total: 100),
          _row(2, FileJobStatus.queued),
          _row(3, FileJobStatus.failed, error: const FtError(FtReason.inUse)),
          _row(4, FileJobStatus.waitingConfirm),
          _row(5, FileJobStatus.done, count: 1, total: 88576),
        ]
        ..summary = _summary(
          active: 1,
          queued: 1,
          failed: 1,
          waiting: 1,
          finished: 1,
          progress: 0.24,
        );
      await _pumpQueue(tester, jobs);
      expect(_rich('1 个进行中，1 个排队，1 个失败，1 个等待确认 · 24%'), findsOneWidget);
      expect(find.text('清除已完成'), findsOneWidget);
      expect(find.text('全部继续'), findsNothing);
      await tester.tap(find.text('清除已完成'));
      expect(jobs.calls, ['clearFinished']);
    });

    testWidgets('only paused jobs left: "‹n› 个已暂停" and "全部继续"', (tester) async {
      final jobs = _Jobs()
        ..rows = [
          _row(1, FileJobStatus.paused, done: 2048, total: 4096),
          _row(
            2,
            FileJobStatus.paused,
            done: 0,
            total: 1024,
            notes: const [ResumeUnsupported()],
          ),
        ]
        ..summary = _summary(paused: 2);
      await _pumpQueue(tester, jobs);
      expect(_rich('2 个已暂停'), findsOneWidget);
      expect(find.text('已暂停 · 已传 2.00 KB / 4.00 KB'), findsOneWidget);
      expect(find.text('已暂停 · 已传 0 字节 / 1.00 KB'), findsOneWidget);
      expect(find.text('远程设备的版本不支持断点续传，当前文件将从头传输。'), findsOneWidget);
      await tester.tap(find.text('全部继续'));
      await tester.tap(_button('继续').first);
      expect(jobs.calls, ['resumeAll', 'resume:1']);
    });

    testWidgets(
      'the list is at most six tenths of the height given; the saved one stays',
      (tester) async {
        fakes.bind.localOptions[kOptionLeapgateFtQueueHeight] = '600';
        final jobs = _Jobs()
          ..rows = [
            _row(
              1,
              FileJobStatus.inProgress,
              done: 1,
              total: 2,
              remaining: const Duration(seconds: 3580),
            ),
          ]
          ..summary = _summary(active: 1);
        // A window 400 high, the panel below the panes as the file view lays it out: the
        // column leaves its height unbounded, so the window's counts.
        tester.view.physicalSize = const Size(1280, 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(
            SizedBox(
              height: 400,
              child: Column(
                children: [
                  const Expanded(child: SizedBox.expand()),
                  FileQueuePanel(jobs: jobs),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(ListView)).height, 240);
        expect(fakes.bind.localOptions[kOptionLeapgateFtQueueHeight], '600');
        // 59 minutes 40 seconds is about an hour, not "60 分钟".
        expect(find.textContaining('剩余约 1 小时 0 分钟'), findsOneWidget);
      },
    );

    testWidgets('not connected: no "继续" and no "全部继续"', (tester) async {
      final session = appCore.sessions.open('100200300', ConnType.fileTransfer);
      final jobs = _Jobs()
        ..rows = [_row(1, FileJobStatus.paused, done: 1024, total: 2048)]
        ..summary = _summary(paused: 1);
      await _pumpQueue(tester, jobs, connection: session.connection);
      expect(session.connection.stage, isNot(ConnStage.connected));
      expect(_rich('1 个已暂停'), findsOneWidget);
      expect(find.text('全部继续'), findsNothing);
      expect(_button('继续'), findsNothing);
      expect(_button('取消'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await appCore.sessions.closeDevice('100200300');
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('each state says what it is and offers its buttons', (
      tester,
    ) async {
      final jobs = _Jobs()
        ..rows = [
          _row(
            1,
            FileJobStatus.inProgress,
            done: 639631360,
            total: 1417339208,
            index: 3,
            count: 12,
            speed: 1258291,
            remaining: const Duration(minutes: 10),
          ),
          _row(2, FileJobStatus.counting),
          _row(
            3,
            FileJobStatus.deleting,
            direction: FileJobDirection.delete,
            index: 37,
            count: 120,
          ),
          _row(4, FileJobStatus.interrupted),
          _row(5, FileJobStatus.skipped),
          _row(6, FileJobStatus.cancelled),
          _row(7, FileJobStatus.done, count: 0),
          _row(
            8,
            FileJobStatus.failed,
            error: const FtError(FtReason.diskFull),
          ),
          _row(
            9,
            FileJobStatus.failed,
            error: const FtError(FtReason.other, text: 'Wrong id'),
          ),
        ]
        ..summary = _summary(active: 2, failed: 2, finished: 3);
      // Tall enough for every row to be built.
      fakes.bind.localOptions[kOptionLeapgateFtQueueHeight] = '600';
      await _pumpQueue(tester, jobs);
      expect(
        find.text(
          '45% · 610 MB / 1.32 GB · 3 / 12 个文件 · 1.20 MB/s · 剩余约 10 分钟',
        ),
        findsOneWidget,
      );
      expect(find.text('正在统计文件…'), findsOneWidget);
      expect(find.text('正在删除… 37 / 120 个文件'), findsOneWidget);
      expect(find.text('已中断，重新连接后将继续'), findsOneWidget);
      expect(find.text('已跳过：目标位置已有同名文件'), findsOneWidget);
      expect(find.text('已取消'), findsOneWidget);
      expect(find.text('已完成 · 0 个文件，0 字节'), findsOneWidget);
      // A download fills this device.
      expect(find.text('失败：本机的磁盘空间不足'), findsOneWidget);
      expect(find.text('传输失败'), findsOneWidget);
      expect(find.text(r'D:\备份\照片 → C:\Users\u\Pictures'), findsWidgets);

      // Running rows cancel, finished ones go from the list.
      expect(_button('取消'), findsNWidgets(4));
      expect(_button('移除'), findsNWidgets(5));
      await tester.tap(_button('取消').first);
      await tester.tap(_button('移除').first);
      expect(jobs.calls, ['cancel:1', 'remove:5']);
    });

    testWidgets(
      'a new job expands it once; collapsed by hand it waits for the next',
      (tester) async {
        final jobs = _Jobs();
        await _pumpQueue(tester, jobs);
        jobs
          ..rows = [_row(1, FileJobStatus.queued)]
          ..summary = _summary(queued: 1)
          ..changed();
        await tester.pump();
        expect(find.text('排队中'), findsOneWidget);

        await tester.tap(find.text('收起'));
        await tester.pump();
        expect(find.text('排队中'), findsNothing);
        jobs
          ..summary = _summary(active: 1)
          ..changed();
        await tester.pump();
        expect(find.text('展开'), findsOneWidget);

        jobs
          ..rows = [...jobs.rows, _row(2, FileJobStatus.queued)]
          ..changed();
        await tester.pump();
        expect(find.text('收起'), findsOneWidget);
      },
    );
  });

  group('the dialogs (02 blocks I and J, §3.1)', () {
    late TabOverlays overlays;

    Future<void> pumpScope(WidgetTester tester) async {
      overlays = TabOverlays();
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(Overlay(key: overlays.keyOf('dev'))));
    }

    testWidgets(
      'replace: the same two files start on "跳过", the box goes with the answer',
      (tester) async {
        await pumpScope(tester);
        final answer = showFilePrompt(
          overlays,
          'dev',
          const FtOverwritePrompt(
            name: '年度报告.docx',
            folder: r'C:\Users\u\Documents',
            kind: FtOverwriteKind.identical,
          ),
        );
        await tester.pump();
        expect(find.text('替换“年度报告.docx”？'), findsOneWidget);
        expect(
          find.text(r'目标文件夹“C:\Users\u\Documents”中已有同名文件。'),
          findsOneWidget,
        );
        expect(find.text('两个文件的大小和修改时间相同。'), findsOneWidget);
        await tester.tap(find.text('对此次传输中的其他冲突执行相同操作'));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(await answer, (choice: OverwriteChoice.skip, forAll: true));
      },
    );

    testWidgets('replace: temporary files only, and closed without an answer', (
      tester,
    ) async {
      await pumpScope(tester);
      final answer = showFilePrompt(
        overlays,
        'dev',
        const FtOverwritePrompt(
          name: 'a.zip',
          folder: r'D:\备份',
          kind: FtOverwriteKind.tempOnly,
        ),
      );
      await tester.pump();
      expect(find.text(r'目标文件夹“D:\备份”中有上次未完成传输留下的临时文件。'), findsOneWidget);
      expect(find.text('取消传输'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(await answer, isNull);
    });

    testWidgets('delete: counting, then the count and size; "删除" answers yes', (
      tester,
    ) async {
      await pumpScope(tester);
      final state = ValueNotifier<FtDeleteState>(const FtDeleteCounting());
      final answer = showFilePrompt(
        overlays,
        'dev',
        FtDeletePrompt(isRemote: true, state: state, retry: () {}),
      );
      await tester.pump();
      expect(find.text('正在统计要删除的项目…'), findsOneWidget);
      state.value = const FtDeleteReady(
        kind: FtDeleteKind.contents,
        name: '照片',
        items: 3,
        files: 12,
        bytes: 2048,
      );
      await tester.pump();
      expect(find.text('永久删除这 3 个项目？'), findsOneWidget);
      expect(find.text('将从远程设备上删除 12 个文件（2.00 KB），无法恢复。'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pump();
      expect(await answer, true);
    });

    testWidgets('delete: a link, a count that failed (retry), over the limit', (
      tester,
    ) async {
      await pumpScope(tester);
      var retried = 0;
      final state = ValueNotifier<FtDeleteState>(
        const FtDeleteReady(kind: FtDeleteKind.link, name: '旧照片'),
      );
      final answer = showFilePrompt(
        overlays,
        'dev',
        FtDeletePrompt(isRemote: false, state: state, retry: () => retried++),
      );
      await tester.pump();
      expect(find.text('删除符号链接“旧照片”？'), findsOneWidget);
      expect(find.text('只删除符号链接本身，其指向的内容不受影响。'), findsOneWidget);

      state.value = const FtDeleteCountFailed(
        folder: '备份',
        error: FtError(FtReason.permissionDenied),
      );
      await tester.pump();
      expect(find.text('无法统计“备份”中的文件。没有访问权限。'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, 1);

      state.value = const FtDeleteOverLimit(
        folder: '备份',
        limit: 1000,
        count: 5000,
      );
      await tester.pump();
      expect(
        find.text('远程设备限制了单次操作的文件数量（最多 1000 个），“备份”中有 5000 个文件。'),
        findsOneWidget,
      );
      await tester.tap(find.text('关闭'));
      await tester.pump();
      expect(await answer, isNull);
    });

    testWidgets(
      'new folder: checked while typing, the button waits for the result and a failure '
      'stays in the dialog',
      (tester) async {
        await pumpScope(tester);
        FtError? result = const FtError(FtReason.permissionDenied);
        final submitted = <String>[];
        final answer = showFilePrompt(
          overlays,
          'dev',
          FtNewFolderPrompt(
            isWindows: true,
            check: (name) => name.contains(':')
                ? FtNameError.invalidChars
                : name == '照片'
                ? FtNameError.alreadyExists
                : null,
            submit: (name) async {
              submitted.add(name);
              return result;
            },
          ),
        );
        await tester.pump();
        expect(find.text('新建文件夹'), findsWidgets);
        final field = find.byType(EditableText);
        expect(tester.widget<EditableText>(field).controller.text, '新建文件夹');

        await tester.enterText(field, 'a:b');
        await tester.pump();
        expect(find.text(r'名称不能包含下列字符：\ / : * ? " < > |'), findsOneWidget);
        await tester.tap(find.text('新建'));
        expect(submitted, isEmpty);

        await tester.enterText(field, '照片');
        await tester.pump();
        expect(find.text('此位置已有同名的文件或文件夹'), findsOneWidget);

        await tester.enterText(field, '资料');
        await tester.pump();
        await tester.tap(find.text('新建'));
        await tester.pump();
        expect(submitted, ['资料']);
        expect(find.text('无法新建文件夹。没有访问权限。'), findsOneWidget);

        result = null;
        await tester.tap(find.text('新建'));
        await tester.pump();
        expect(await answer, '资料');
      },
    );

    testWidgets('new folder: Esc waits while the name is submitted', (
      tester,
    ) async {
      await pumpScope(tester);
      final made = Completer<FtError?>();
      final answer = showFilePrompt(
        overlays,
        'dev',
        FtNewFolderPrompt(
          isWindows: true,
          check: (_) => null,
          submit: (_) => made.future,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('新建'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('新建'), findsOneWidget);
      made.complete(null);
      await tester.pump();
      expect(await answer, '新建文件夹');
    });

    testWidgets(
      'rename: the name up to its extension selected, unchanged is off',
      (tester) async {
        await pumpScope(tester);
        final submitted = <String>[];
        final answer = showFilePrompt(
          overlays,
          'dev',
          FtRenamePrompt(
            name: '年度报告.docx',
            isDirectory: false,
            isWindows: false,
            check: (name) =>
                name.contains('/') ? FtNameError.invalidChars : null,
            submit: (name) async {
              submitted.add(name);
              return null;
            },
          ),
        );
        await tester.pump();
        expect(find.text('重命名“年度报告.docx”'), findsOneWidget);
        final field = find.byType(EditableText);
        expect(
          tester.widget<EditableText>(field).controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4),
        );
        await tester.tap(find.text('重命名'));
        expect(submitted, isEmpty);

        await tester.enterText(field, 'a/b');
        await tester.pump();
        expect(find.text('名称不能包含 /'), findsOneWidget);
        await tester.enterText(field, '终稿.docx');
        await tester.pump();
        await tester.tap(find.text('重命名'));
        await tester.pump();
        expect(await answer, '终稿.docx');
      },
    );

    testWidgets('disconnect: "断开文件传输？" with the unfinished transfers', (
      tester,
    ) async {
      await pumpScope(tester);
      final answer = showFilePrompt(
        overlays,
        'dev',
        const FtDisconnectPrompt(2),
      );
      await tester.pump();
      expect(find.text('断开文件传输？'), findsOneWidget);
      expect(find.text('2 个传输尚未完成，下次打开文件传输时可继续。'), findsOneWidget);
      await tester.tap(find.text('断开'));
      await tester.pump();
      expect(await answer, true);
    });
  });
}
