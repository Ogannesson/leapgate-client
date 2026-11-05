import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/files/file_view.dart';
import 'package:leapgate_ui/pages/session/connection_panel.dart';
import 'package:leapgate_ui/pages/session/session_page.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/shell/session_views.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';
import 'package:leapgate_ui/widgets/lg_title_bar.dart';

import 'file_transfer_fakes.dart';
import 'session_fakes.dart';

// One session tab with several views (01 §2.1, §3.2 blocks A and G; 02 §2.1.1, §3.1, §3.2;
// `LEAPGATE.md` §10.15 "外壳和文件视图的接口"): opening the file transfer, which view takes the
// keyboard and gets frames, the tab's marks, the close confirmations. Device IDs are made up.

const _id = '100200300';

class _Jobs extends FakeFileJobs {
  void set({int unfinished = 0, double? progress, int waiting = 0}) {
    this.unfinished = unfinished;
    summary = (
      active: progress == null ? 0 : 1,
      queued: 0,
      waitingConfirm: waiting,
      failed: 0,
      paused: 0,
      interrupted: 0,
      finished: 0,
      progress: progress,
    );
    notifyListeners();
  }
}

class _Model extends FakeFileTransferModel {
  final _jobs = _Jobs();

  @override
  _Jobs get jobs => _jobs;
}

void main() {
  late AppFakes fakes;
  final models = <FFI, _Model>{};

  setUp(() {
    fakes = installAppFakes();
    fileTransferFor = (v) => models.putIfAbsent(v, _Model.new);
  });
  tearDown(() {
    fileTransferFor = fileTransferOf;
    models.clear();
  });

  Future<FFI> open(WidgetTester tester, {String id = _id}) async {
    mainNavigation.connect(id);
    await tester.pump();
    await tester.pump();
    return appCore.sessions.sessionsOf(id).first;
  }

  Future<FFI> openFiles(WidgetTester tester, {String id = _id}) async {
    mainNavigation.openFileTransfer(id);
    await tester.pump();
    await tester.pump();
    return appCore.sessions.sessionsOf(id).firstWhere(isFileView);
  }

  _Jobs jobsOf(FFI v) => models[v]!.jobs;

  LgTitleBar titleBar(WidgetTester tester) =>
      tester.widget<LgTitleBar>(find.byType(LgTitleBar));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testMainWindow(
    'file transfer opens in the device\'s tab; the remote desktop behind it lets go of the '
    'keyboard and gets no frames, and takes them back when shown again',
    (tester) async {
      await pumpMainWindow(tester);
      final desk = await open(tester);
      await emit(tester, fakes, desk, connectionReady());
      await emit(tester, fakes, desk, peerInfo());
      fakes.bind.calls.clear();

      final files = await openFiles(tester);
      expect(appCore.sessions.devices, [_id]);
      expect(files.connType, ConnType.fileTransfer);
      expect(
        tester
            .widget<FileView>(find.byType(FileView, skipOffstage: false))
            .active,
        true,
      );
      expect(
        tester
            .widget<SessionPage>(find.byType(SessionPage, skipOffstage: false))
            .active,
        false,
      );
      expect(fakes.lg.visible.last, (desk.sessionId, false));
      expect(callsTo(fakes, #sessionEnterOrLeave).last[#enter], false);

      // The view switch on the file view, or the device menu, shows the remote desktop again.
      mainNavigation.connect(_id);
      await tester.pump();
      expect(appCore.sessions.sessionsOf(_id), hasLength(2));
      expect(
        tester
            .widget<SessionPage>(find.byType(SessionPage, skipOffstage: false))
            .active,
        true,
      );
      expect(
        tester
            .widget<FileView>(find.byType(FileView, skipOffstage: false))
            .active,
        false,
      );
      expect(fakes.lg.visible.last, (desk.sessionId, true));
    },
  );

  testMainWindow(
    'the remote desktop\'s view switch lists both views and opens the file transfer',
    (tester) async {
      await pumpMainWindow(tester);
      final desk = await open(tester);
      await emit(tester, fakes, desk, connectionReady(direct: true));
      await emit(tester, fakes, desk, peerInfo());

      await tester.tap(find.text('远程桌面').first);
      await tester.pumpAndSettle();
      expect(find.text('文件传输'), findsOneWidget);
      expect(find.text('未打开'), findsOneWidget);
      expect(find.text('直连'), findsWidgets);

      await tester.tap(find.text('文件传输'));
      await tester.pump();
      await tester.pump();
      expect(appCore.sessions.sessionsOf(_id).map((v) => v.connType), [
        ConnType.defaultConn,
        ConnType.fileTransfer,
      ]);
      expect(
        tester
            .widget<FileView>(find.byType(FileView, skipOffstage: false))
            .active,
        true,
      );

      // Back on the remote desktop, its switch shows the file transfer's state and progress (the
      // copied file model is not faked for a peer info, so it stays connecting here).
      final files = appCore.sessions.sessionsOf(_id).last;
      jobsOf(files).set(unfinished: 1, progress: 0.45);
      mainNavigation.connect(_id);
      await tester.pump();
      await tester.tap(find.text('远程桌面').first);
      await settle(tester);
      expect(find.text('正在连接… · 45%'), findsOneWidget);
    },
  );

  testMainWindow(
    'the tab: the worst of its views, the transfer ring, the reminder mark while a replace '
    'confirmation waits (02 §3.2)',
    (tester) async {
      await pumpMainWindow(tester);
      final desk = await open(tester);
      await emit(tester, fakes, desk, connectionReady(direct: true));
      await emit(tester, fakes, desk, peerInfo());
      expect(titleBar(tester).sessions.single.status, isA<LgRouteMark>());

      // The file transfer still connecting is the worst.
      final files = await openFiles(tester);
      var tab = titleBar(tester).sessions.single;
      expect((tab.status! as LgStatusText).status, LgStatus.connecting);
      expect(tab.progress, isNull);
      expect(tab.alert, false);

      jobsOf(files).set(unfinished: 1, progress: 0.3);
      await tester.pump();
      tab = titleBar(tester).sessions.single;
      expect(tab.progress, 0.3);
      jobsOf(files).set(unfinished: 1, progress: 0.3, waiting: 1);
      await tester.pump();
      expect(titleBar(tester).sessions.single.alert, true);
    },
  );

  group('closing (01 §3.2 block G, 02 §3.1)', () {
    testMainWindow(
      '"×" with two views asks once, with the transfers sentence',
      (tester) async {
        await pumpMainWindow(tester);
        await open(tester);
        final files = await openFiles(tester);
        jobsOf(files).set(unfinished: 2);

        titleBar(tester).onCloseTab(1);
        await settle(tester);
        expect(find.text('断开与此设备的 2 个会话？'), findsOneWidget);
        expect(find.text('2 个传输尚未完成，下次打开文件传输时可继续。'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await settle(tester);
        expect(appCore.sessions.sessionsOf(_id), hasLength(2));

        titleBar(tester).onCloseTab(1);
        await settle(tester);
        await tester.tap(find.text('断开'));
        await settle(tester);
        expect(appCore.sessions.devices, isEmpty);
      },
    );

    testMainWindow('the remote desktop\'s "关闭标签" shortcut asks as "×" does', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final desk = await open(tester);
      await emit(tester, fakes, desk, connectionReady());
      await emit(tester, fakes, desk, peerInfo());
      await openFiles(tester);
      mainNavigation.connect(_id);
      await tester.pump();

      desk.shortcutModel.onTriggered(kShortcutActionCloseTab);
      await settle(tester);
      expect(find.text('断开与此设备的 2 个会话？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle(tester);
      expect(appCore.sessions.sessionsOf(_id), hasLength(2));
    });

    testMainWindow(
      'the remote desktop\'s connection panel beside a file view: "关闭远程桌面"',
      (tester) async {
        await pumpMainWindow(tester);
        final desk = await open(tester);
        await openFiles(tester);
        mainNavigation.connect(_id);
        await tester.pump();
        fakes.lg.reasons['nope'] = 'not_allowed';
        await emit(
          tester,
          fakes,
          desk,
          msgbox('error', 'Connection Error', 'nope'),
        );
        expect(find.text('关闭标签'), findsNothing);
        await tester.tap(find.text('关闭远程桌面'));
        await settle(tester);
        expect(
          appCore.sessions.sessionsOf(_id).single.connType,
          ConnType.fileTransfer,
        );
      },
    );

    testMainWindow(
      'a tab of the file transfer alone: closes at once, or asks as "断开" with '
      'unfinished transfers',
      (tester) async {
        await pumpMainWindow(tester);
        await openFiles(tester);
        titleBar(tester).onCloseTab(1);
        await settle(tester);
        expect(appCore.sessions.devices, isEmpty);

        final files = await openFiles(tester);
        jobsOf(files).set(unfinished: 1);
        titleBar(tester).onCloseTab(1);
        await settle(tester);
        expect(find.text('断开文件传输？'), findsOneWidget);
        expect(find.text('1 个传输尚未完成，下次打开文件传输时可继续。'), findsOneWidget);
        await tester.tap(find.text('断开'));
        await settle(tester);
        expect(appCore.sessions.devices, isEmpty);
      },
    );

    testMainWindow(
      'the view\'s "断开" asks with unfinished transfers and closes that view only',
      (tester) async {
        await pumpMainWindow(tester);
        await open(tester);
        final files = await openFiles(tester);
        jobsOf(files).set(unfinished: 3);

        tester
            .widget<FileView>(find.byType(FileView, skipOffstage: false))
            .onDisconnect();
        await settle(tester);
        expect(find.text('断开文件传输？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await settle(tester);
        expect(appCore.sessions.sessionsOf(_id), hasLength(2));

        tester
            .widget<FileView>(find.byType(FileView, skipOffstage: false))
            .onDisconnect();
        await settle(tester);
        await tester.tap(find.text('断开'));
        await settle(tester);
        expect(
          appCore.sessions.sessionsOf(_id).single.connType,
          ConnType.defaultConn,
        );
        expect(
          tester.widget<SessionPage>(find.byType(SessionPage)).active,
          true,
        );
      },
    );

    testMainWindow(
      'the tab menu: "打开文件传输" while there is none, "关闭" as "×", "关闭其他标签" '
      'asks only for unfinished transfers',
      (tester) async {
        await pumpMainWindow(tester);
        await open(tester);
        titleBar(tester).onTabContextMenu!(1, const Offset(300, 20));
        await settle(tester);
        await tester.tap(find.text('打开文件传输'));
        await tester.pump();
        await tester.pump();
        expect(appCore.sessions.sessionsOf(_id), hasLength(2));

        titleBar(tester).onTabContextMenu!(1, const Offset(300, 20));
        await settle(tester);
        expect(find.text('打开文件传输'), findsNothing);
        await tester.tap(find.text('关闭').last);
        await settle(tester);
        expect(find.text('断开与此设备的 2 个会话？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await settle(tester);

        // Another tab, then "关闭其他标签" from it: the transfers of this one are asked about.
        final files = appCore.sessions.sessionsOf(_id).last;
        jobsOf(files).set(unfinished: 1);
        await open(tester, id: '400500600');
        titleBar(tester).onTabContextMenu!(2, const Offset(500, 20));
        await settle(tester);
        await tester.tap(find.text('关闭其他标签'));
        await settle(tester);
        expect(find.text('关闭其他标签？'), findsOneWidget);
        await tester.tap(find.text('关闭').last);
        await settle(tester);
        expect(appCore.sessions.devices, ['400500600']);
      },
    );

    testMainWindow(
      'closing the window after "不再提示" still asks while transfers are unfinished',
      (tester) async {
        fakes.bind.localOptions[kOptionEnableConfirmClosingTabs] = 'N';
        fakes.bind.localOptions['leapgate-close-action'] = 'exit';
        await pumpMainWindow(tester);
        final files = await openFiles(tester);
        jobsOf(files).set(unfinished: 2);

        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is LgIcon && w.icon == LgIcons.windowClose,
          ),
        );
        await settle(tester);
        expect(find.text('关闭窗口？'), findsOneWidget);
        expect(find.text('2 个传输尚未完成，下次打开文件传输时可继续。'), findsOneWidget);
        expect(find.text('不再提示'), findsNothing);
        await tester.tap(find.text('关闭').last);
        await settle(tester);
        expect(fakes.window, contains('close'));
      },
    );

    testMainWindow(
      'the window close confirmation adds the transfers sentence',
      (tester) async {
        fakes.bind.installed = true;
        await pumpMainWindow(tester);
        final files = await openFiles(tester);
        jobsOf(files).set(unfinished: 1);

        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is LgIcon && w.icon == LgIcons.windowClose,
          ),
        );
        await settle(tester);
        expect(find.text('断开全部 1 个会话并关闭窗口？'), findsOneWidget);
        expect(find.text('1 个传输尚未完成，下次打开文件传输时可继续。'), findsOneWidget);
        expect(find.text('不再提示'), findsOneWidget);
      },
    );
  });

  testWidgets(
    'the connection panel of a view with others beside it: "关闭文件传输" closes that view',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final desk = appCore.sessions.open(_id, ConnType.defaultConn);
      final files = appCore.sessions.open(_id, ConnType.fileTransfer);
      fakes.lg.reasons['nope'] = 'not_allowed';
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildLgTheme(
            brightness: Brightness.light,
            mode: LgMode.compact,
          ),
          home: Scaffold(
            body: ConnectionPanel(ffi: files, active: true, lastView: false),
          ),
        ),
      );
      await emit(
        tester,
        fakes,
        files,
        msgbox('error', 'Connection Error', 'nope'),
      );
      expect(find.text('关闭标签'), findsNothing);
      await tester.tap(find.text('关闭文件传输'));
      await tester.pump();
      expect(appCore.sessions.sessionsOf(_id), [desk]);
      await tester.pumpWidget(const SizedBox());
      await appCore.sessions.closeDevice(_id);
      await tester.pump(const Duration(seconds: 10));
    },
  );
}
