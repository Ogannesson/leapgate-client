import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/file_transfer/errors.dart';
import 'package:flutter_hbb/leapgate/file_transfer/file_model.dart';
import 'package:flutter_hbb/leapgate/file_transfer/file_transfer_api.dart';
import 'package:flutter_hbb/leapgate/file_transfer/jobs.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/leapgate/file_transfer/sort.dart';
import 'package:flutter_hbb/leapgate/prompts.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';
import 'file_transfer_fakes.dart';

// The rewritten file transfer model (`LEAPGATE.md` §10.15 "测试" A). Test names give the
// upstream place where the flow came from (flutter/lib/models/file_model.dart@bd9262397).

/// Block 1 with the file transfer calls these tests make.
class FtBind extends FakeBind {
  /// What reading this device's empty folders answers, as Rust's JSON.
  String emptyDirs = '[]';

  /// This device's home folder and the peer options a session reads back.
  String home = '';
  final peerOptions = <String, String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #mainGetHomeDir:
        return Future<String>.value(home);
      case #sessionGetPeerOption:
        return Future<String>.value(
            peerOptions[invocation.namedArguments[#name]] ?? '');
      case #sessionSendFiles:
      case #sessionCreateDir:
      case #sessionReadRemoteDir:
      case #sessionReadRemoteEmptyDirsRecursiveSync:
      case #mainSetLocalOption:
        calls.add(invocation);
        return Future<void>.value();
      case #sessionReadLocalEmptyDirsRecursiveSync:
        calls.add(invocation);
        return Future<String>.value(emptyDirs);
    }
    return super.noSuchMethod(invocation);
  }
}

/// Answers each question with [onAsk] and keeps them.
class TestPrompter implements Prompter {
  TestPrompter(this.onAsk);

  final FutureOr<Object?> Function(Prompt prompt) onAsk;
  final asked = <Prompt>[];

  @override
  Future<T?> ask<T>(Prompt<T> prompt, {FFI? session}) async {
    asked.add(prompt);
    return await onAsk(prompt) as T?;
  }
}

typedef _Setup = ({FtBind bind, FFI s, FakeFileTransferApi api});

/// A connected file transfer session to a [platform] peer.
_Setup _session({String platform = 'Linux', String version = '1.4.5'}) {
  installFakes();
  final bind = FtBind();
  platformFFI.setBindingForTesting(bind);
  final api = FakeFileTransferApi();
  fileTransferApi = api;
  final s = appCore.sessions.open('100200300', ConnType.fileTransfer);
  s.ffiModel.pi
    ..platform = platform
    ..version = version;
  s.connection.onPeerInfo();
  return (bind: bind, s: s, api: api);
}

Map<String, dynamic> _json(String name,
        {int type = 4, int size = 1, int modified = 0}) =>
    {'entry_type': type, 'modified_time': modified, 'name': name, 'size': size};

Entry _entry(String path, {int type = 4, int size = 1}) => Entry()
  ..entryType = type
  ..name = path.split(RegExp(r'[\\/]')).last
  ..path = path
  ..size = size;

/// What Rust sends for a remote folder, or for a count before a delete ([id] > 0).
void _dir(FFI s, String path, List<Map<String, dynamic>> entries,
        {int id = 0}) =>
    s.fileModel.receiveFileDir({
      'is_local': 'false',
      'value': jsonEncode({'id': id, 'path': path, 'entries': entries}),
    });

List<Object?> _args(FtBind bind, Symbol call, Symbol arg) =>
    [for (final c in bind.callsTo(call)) c.namedArguments[arg]];

Map<String, dynamic> _overwrite(int id, String path,
        {bool upload = true, bool identical = false}) =>
    {
      'id': '$id',
      'file_num': '0',
      'read_path': path,
      'is_upload': '$upload',
      'is_identical': '$identical',
    };

void main() {
  tearDown(() => fileTransferApi = const RustFileTransferApi());

  group('overwrite confirmation (file_model.dart:166-213 overrideFileConfirm)', () {
    final cases = <(String, OverwriteAnswer?, bool?, bool)>[
      // (answer, prompter's answer, needOverride sent or null for "cancelled", remember)
      ('overwrite', (choice: OverwriteChoice.overwrite, forAll: false), true, false),
      ('overwrite for all', (choice: OverwriteChoice.overwrite, forAll: true), true, true),
      ('skip', (choice: OverwriteChoice.skip, forAll: false), false, false),
      ('skip for all', (choice: OverwriteChoice.skip, forAll: true), false, true),
      ('cancel', (choice: OverwriteChoice.cancel, forAll: false), null, false),
      ('cancel for all', (choice: OverwriteChoice.cancel, forAll: true), null, false),
      ('closed without an answer is cancel', null, null, false),
    ];
    for (final (name, answer, needOverride, remember) in cases) {
      test(name, () async {
        final t = _session();
        final prompter = TestPrompter((_) => answer);
        appCore.prompter = prompter;
        final jobs = t.s.fileModel.jobController;
        final id = jobs.addTransferJob(Entry()..path = '/a.txt', false);
        jobs.registerTransferConflictBatch([id]);

        await t.s.fileModel.overrideFileConfirm(_overwrite(id, '/a.txt'));

        expect(prompter.asked.single, isA<FtOverwritePrompt>());
        final sent = t.bind.callsTo(#sessionSetConfirmOverrideFile);
        final cancelled = t.bind.callsTo(#sessionCancelJob);
        if (needOverride == null) {
          expect(sent, isEmpty);
          expect(cancelled.single.namedArguments[#actId], id);
        } else {
          expect(cancelled, isEmpty);
          final args = sent.single.namedArguments;
          expect(args[#actId], id);
          expect(args[#needOverride], needOverride);
          expect(args[#remember], remember);
        }
      });
    }
  });

  group('what the replace confirmation says (M7a-5)', () {
    test('a download looks at this device: the file, only its temporary files, or neither',
        () async {
      final t = _session();
      final prompts = <FtOverwritePrompt>[];
      appCore.prompter = TestPrompter((q) {
        prompts.add(q as FtOverwritePrompt);
        return (choice: OverwriteChoice.skip, forAll: false);
      });
      final dir = io.Directory.systemTemp.createTempSync('lg-ft-');
      addTearDown(() => dir.deleteSync(recursive: true));
      io.File(p.join(dir.path, 'a.txt')).writeAsStringSync('a');
      io.File(p.join(dir.path, 'b.txt.download')).writeAsStringSync('b');
      final remote = t.s.fileModel.remoteController;
      await remote.transfer(
          [for (final n in ['a.txt', 'b.txt', 'c.txt', 'd.txt']) _entry('/r/$n')],
          to: dir.path);
      final ids = [for (final r in t.s.fileModel.jobs.rows) r.id];

      for (final (i, n) in ['a.txt', 'b.txt', 'c.txt', 'd.txt'].indexed) {
        await t.s.fileModel.postOverrideFileConfirm(_overwrite(
            ids[i], p.join(dir.path, n),
            upload: false, identical: n == 'd.txt'));
      }
      await settle();

      expect(prompts.map((q) => q.kind), [
        FtOverwriteKind.existing,
        FtOverwriteKind.tempOnly,
        FtOverwriteKind.existingOrTemp,
        FtOverwriteKind.identical,
      ]);
      expect(prompts.first.name, 'a.txt');
      expect(p.equals(prompts.first.folder, dir.path), isTrue);
    });

    test('an upload decides from the remote pane when it shows the destination; one question '
        'at a time, the rows waiting meanwhile', () async {
      final t = _session();
      final answers = <Completer<OverwriteAnswer>>[];
      final prompts = <FtOverwritePrompt>[];
      appCore.prompter = TestPrompter((q) {
        prompts.add(q as FtOverwritePrompt);
        answers.add(Completer());
        return answers.last.future;
      });
      final model = t.s.fileModel;
      model.remoteController.setShowHidden(true);
      final opened = model.remoteController.openDirectory('/home/u');
      await settle();
      _dir(t.s, '/home/u', [_json('a.txt'), _json('b.txt.digest')]);
      expect(await opened, isNull);
      await model.localController.transfer(
          [_entry('C:\\src\\a.txt'), _entry('C:\\src\\b.txt'), _entry('C:\\src\\c.txt')]);
      await model.localController
          .transfer([_entry('C:\\src\\d', type: 0)], to: '/other');
      final ids = [for (final r in model.jobs.rows) r.id];

      await model.postOverrideFileConfirm(_overwrite(ids[0], 'C:\\src\\a.txt'));
      await model.postOverrideFileConfirm(_overwrite(ids[1], 'C:\\src\\b.txt'));
      await settle();
      expect(prompts, hasLength(1));
      expect(model.jobs.rows.take(2).map((r) => r.status),
          everyElement(FileJobStatus.waitingConfirm));
      expect(model.jobs.summary.waitingConfirm, 2);

      answers[0].complete((choice: OverwriteChoice.skip, forAll: false));
      await settle();
      expect(prompts, hasLength(2));
      expect(_args(t.bind, #sessionSetConfirmOverrideFile, #actId), [ids[0]]);
      expect(model.jobs.rows.first.status, isNot(FileJobStatus.waitingConfirm));
      answers[1].complete((choice: OverwriteChoice.skip, forAll: false));

      await model.postOverrideFileConfirm(_overwrite(ids[2], 'C:\\src\\c.txt'));
      await settle();
      answers[2].complete((choice: OverwriteChoice.skip, forAll: false));
      await model
          .postOverrideFileConfirm(_overwrite(ids[3], 'C:\\src\\d\\sub\\x.txt'));
      await settle();
      answers[3].complete((choice: OverwriteChoice.skip, forAll: false));
      // Without hidden items the file may be there, hidden, next to a visible temporary one.
      model.remoteController.setShowHidden(false);
      await model.postOverrideFileConfirm(_overwrite(ids[1], 'C:\\src\\b.txt'));
      await settle();
      answers[4].complete((choice: OverwriteChoice.skip, forAll: false));

      expect(prompts.map((q) => (q.name, q.folder, q.kind)), [
        ('a.txt', '/home/u', FtOverwriteKind.existing),
        ('b.txt', '/home/u', FtOverwriteKind.tempOnly),
        // Shown, but not in the list read: stale or hidden.
        ('c.txt', '/home/u', FtOverwriteKind.existingOrTemp),
        ('x.txt', '/other/d/sub', FtOverwriteKind.existingOrTemp),
        ('b.txt', '/home/u', FtOverwriteKind.existingOrTemp),
      ]);
    });
  });

  group('queue rows (02 §2.2 block H)', () {
    test('one job at a time in each direction; a folder counts first; speed and time left '
        'from the progress bytes', () async {
      final t = _session();
      final model = t.s.fileModel;
      final jobs = model.jobController;
      await model.localController.transfer(
          [_entry('C:\\a.bin', size: 1000), _entry('C:\\b.bin', size: 10)],
          to: '/home/u');
      await model.remoteController
          .transfer([_entry('/r.txt', size: 0)], to: 'C:\\dl');
      await model.localController
          .transfer([_entry('C:\\dir', type: 0, size: 0)], to: '/home/u');
      var rows = model.jobs.rows;
      expect(rows.map((r) => (r.direction, r.status, r.to)), [
        (FileJobDirection.upload, FileJobStatus.inProgress, '/home/u'),
        (FileJobDirection.upload, FileJobStatus.queued, '/home/u'),
        (FileJobDirection.download, FileJobStatus.inProgress, 'C:\\dl'),
        (FileJobDirection.upload, FileJobStatus.queued, '/home/u'),
      ]);
      expect(model.jobs.unfinished, 4);
      expect(model.jobs.summary.active, 2);
      expect(model.jobs.summary.queued, 2);
      // Rust reports the waiting jobs' progress too: still queued.
      jobs.tryUpdateJobProgress(
          {'id': '${rows[1].id}', 'file_num': '-1', 'speed': '0', 'finished_size': '0'});
      expect(model.jobs.rows[1].status, FileJobStatus.queued);
      expect(model.jobs.summary.active, 2);

      final start = DateTime(2026, 11, 5, 12);
      T at<T>(int seconds, T Function() f) =>
          withClock(Clock(() => start.add(Duration(seconds: seconds))), f);
      void progress(int id, int bytes, int seconds) =>
          at(seconds, () => jobs.tryUpdateJobProgress({
                'id': '$id',
                'file_num': '0',
                'speed': '0',
                'finished_size': '$bytes',
              }));
      FileJobRow first(int seconds) => at(seconds, () => model.jobs.rows[0]);
      progress(rows[0].id, 100, 0);
      progress(rows[0].id, 200, 1);
      expect(first(1).bytesPerSecond, 100);
      expect(first(1).remaining, isNull, reason: 'not steady yet');
      progress(rows[0].id, 500, 4);
      expect(first(4).bytesPerSecond, 100);
      expect(first(4).remaining, const Duration(seconds: 5));
      // Stalled: no bytes over the last 10 s.
      expect(first(70).bytesPerSecond, 0);
      expect(first(70).remaining, isNull);
      // a.bin and the queued b.bin; the other two have no size yet.
      expect(model.jobs.summary.progress, closeTo(500 / 1010, 1e-9));

      await model.onJobDone({'id': '${rows[0].id}', 'file_num': '0'});
      rows = model.jobs.rows;
      expect(rows[0].status, FileJobStatus.done);
      expect(rows[1].status, FileJobStatus.inProgress);
      // The folder waits behind b.bin; on its own it would be counting.
      model.jobs.cancel(rows[1].id);
      expect(model.jobs.rows[3].status, FileJobStatus.counting);
      jobs.updateFolderFiles({
        'info': jsonEncode({'id': rows[3].id, 'num_entries': 3, 'total_size': 30.0})
      });
      expect(model.jobs.rows[3].status, FileJobStatus.inProgress);
      expect(model.jobs.rows[1].status, FileJobStatus.cancelled);
      expect(_args(t.bind, #sessionCancelJob, #actId), [rows[1].id]);

      model.jobs.clearFinished();
      expect(model.jobs.rows.map((r) => r.name), ['r.txt', 'dir']);
    });

    test('rows under way are interrupted while reconnecting, paused when the session ended',
        () async {
      final t = _session();
      final model = t.s.fileModel;
      await model.localController.transfer([_entry('C:\\a.bin')], to: '/home/u');
      t.s.connection.reconnect(false);
      expect(model.jobs.rows.single.status, FileJobStatus.interrupted);
      expect(model.jobs.unfinished, 0);
      t.s.connection.showMsgBox('error', 'Connection Error', 'Reset by peer', false);
      expect(model.jobs.rows.single.status, FileJobStatus.paused);
      t.s.connection.onPeerInfo();
      expect(model.jobs.rows.single.status, FileJobStatus.inProgress);
    });

    test('failed rows carry FT2\'s reason for the job\'s error, a cancel is not a failure',
        () async {
      final t = _session();
      final sides = <FtSide>[];
      t.api.onReason = (text, platform, side) {
        sides.add(side);
        return FtError(FtReason.diskFull, text: text);
      };
      final model = t.s.fileModel;
      await model.localController
          .transfer([_entry('C:\\a.bin'), _entry('C:\\b.bin')], to: '/home/u');
      final ids = [for (final r in model.jobs.rows) r.id];
      model.handleJobError({'id': '${ids[0]}', 'err': 'No space (os error 28)', 'file_num': '0'});
      model.handleJobError({'id': '${ids[1]}', 'err': 'cancel', 'file_num': '0'});

      final rows = model.jobs.rows;
      expect(rows[0].status, FileJobStatus.failed);
      expect(rows[0].error?.reason, FtReason.diskFull);
      expect(rows[1].status, FileJobStatus.cancelled);
      expect(sides, [FtSide.unknown]);
      model.jobs.clearFinished();
      expect(model.jobs.rows.map((r) => r.status), [FileJobStatus.failed]);
    });

    test('an upload that had an error stays failed when its job_done comes after', () async {
      final t = _session();
      t.api.onReason =
          (text, platform, side) => FtError(FtReason.permissionDenied, text: text);
      final model = t.s.fileModel;
      await model.localController.transfer([_entry('C:\\a.txt')], to: '/home/u');
      final id = model.jobs.rows.single.id;
      model.handleJobError(
          {'id': '$id', 'err': 'Access is denied. (os error 5)', 'file_num': '0'});
      await model.onJobDone({'id': '$id', 'file_num': '0'});

      final row = model.jobs.rows.single;
      expect((row.status, row.error?.reason),
          (FileJobStatus.failed, FtReason.permissionDenied));
      expect(model.jobs.summary.failed, 1);
    });

    test('folders go with their hidden items; nothing goes into "此电脑" (R2-Q22)', () async {
      final t = _session(platform: 'Windows');
      t.bind.emptyDirs =
          jsonEncode([{'id': 0, 'path': 'C:\\d\\empty', 'entries': []}]);
      final model = t.s.fileModel;
      expect(model.localController.showHidden, isFalse);
      await model.localController.transfer([_entry('C:\\d', type: 0)], to: 'D:\\x');
      await model.localController.transfer([_entry('C:\\e', type: 0)], to: '/');
      expect(_args(t.bind, #sessionSendFiles, #includeHidden), [true]);
      expect(_args(t.bind, #sessionSendFiles, #to), ['D:\\x\\d']);
      expect(_args(t.bind, #sessionReadLocalEmptyDirsRecursiveSync, #includeHidden),
          [true]);

      // The empty folder counts once it was made.
      final mkdir = t.bind.callsTo(#sessionCreateDir).single.namedArguments;
      expect((mkdir[#path], mkdir[#isRemote]), ('D:\\x\\d\\empty', true));
      expect(model.jobs.rows.single.folderCount, 0);
      await model.onJobDone({'id': '${mkdir[#actId]}', 'file_num': '-1'});
      expect(model.jobs.rows.single.folderCount, 1);
    });

    test('a delete under way fails when the connection goes; one whose request could not go '
        'fails at once', () async {
      final t = _session();
      t.bind.failing.add(#sessionRemoveFile);
      appCore.prompter = TestPrompter((_) => true);
      final local = t.s.fileModel.localController;
      await local.delete([_entry('C:\\f.txt')]);
      expect(t.s.fileModel.jobs.rows.single.status, FileJobStatus.failed);

      t.bind.failing.clear();
      appCore.prompter = TestPrompter((q) {
        final state = (q as FtDeletePrompt).state;
        final ready = Completer<bool>();
        state.addListener(() {
          if (state.value is FtDeleteReady) ready.complete(true);
        });
        return ready.future;
      });
      final done = local.delete([_entry('C:\\d', type: 0)]);
      await settle();
      final count =
          t.bind.callsTo(#sessionReadDirToRemoveRecursive).single.namedArguments;
      _dir(t.s, 'C:\\d', [_json('a'), _json('b')], id: count[#actId] as int);
      await settle();
      expect(_args(t.bind, #sessionRemoveFile, #path), ['C:\\f.txt', 'C:\\d\\a']);
      expect(t.s.fileModel.jobs.rows.last.status, FileJobStatus.deleting);

      t.s.connection.reconnect(false);
      t.s.connection.onPeerInfo();
      // The answer to the file in flight comes after reconnecting; nothing more is sent.
      final first = t.bind.callsTo(#sessionRemoveFile).last.namedArguments;
      await t.s.fileModel
          .onJobDone({'id': '${first[#actId]}', 'file_num': '0'});
      await done;
      expect(_args(t.bind, #sessionRemoveFile, #path), ['C:\\f.txt', 'C:\\d\\a']);
      final row = t.s.fileModel.jobs.rows.last;
      expect((row.status, row.error?.reason),
          (FileJobStatus.failed, FtReason.disconnected));
    });
  });

  test('folders and drives come first whatever the column; drives are kept', () {
    final list = [
      _entry('b.txt', size: 5)..modifiedTime = 1,
      _entry('A', type: 0)..modifiedTime = 3,
      _entry('C:', type: 3),
      _entry('a.zip', size: 9)..modifiedTime = 2,
      _entry('l', type: 2)..modifiedTime = 4,
    ];
    List<String> names(FileSortField field, bool ascending) =>
        [for (final e in sortEntries(list, (field: field, ascending: ascending))) e.name];

    expect(names(FileSortField.name, true), ['A', 'C:', 'l', 'a.zip', 'b.txt']);
    expect(names(FileSortField.size, false), ['l', 'C:', 'A', 'a.zip', 'b.txt']);
    expect(names(FileSortField.modified, true), ['C:', 'A', 'l', 'b.txt', 'a.zip']);
    expect(names(FileSortField.type, true), ['A', 'C:', 'l', 'b.txt', 'a.zip']);
  });

  group('reading folders', () {
    test('remote folders are read one at a time, so a failure is the read\'s own (10 §4.4)',
        () async {
      final t = _session();
      t.api.onReason = (text, platform, side) =>
          FtError(FtReason.permissionDenied, text: '$side:$text');
      final remote = t.s.fileModel.remoteController;
      final a = remote.openDirectory('/a');
      await settle();
      final b = remote.openDirectory('/b');
      final drives = remote.drives();
      await settle();
      expect(_args(t.bind, #sessionReadRemoteDir, #path), ['/a']);

      t.s.fileModel.handleJobError({'id': '0', 'err': 'denied', 'file_num': '0'});
      final error = await a;
      expect(error?.reason, FtReason.permissionDenied);
      expect(error?.text, 'FtSide.remote:denied');
      await settle();
      expect(_args(t.bind, #sessionReadRemoteDir, #path), ['/a', '/b']);
      _dir(t.s, '/b', [_json('x')]);
      expect(await b, isNull);
      expect(remote.path, '/b');
      expect(remote.entries.single.path, '/b/x');
      // The first read lost to the second: no banner for it.
      expect(remote.openError, isNull);
      expect(await drives, isEmpty, reason: 'a Linux peer has no drives');
    });

    test('a read replaced before its turn is not sent; a job ending while a folder opens '
        'refreshes that folder', () async {
      final t = _session();
      final remote = t.s.fileModel.remoteController;
      final a = remote.openDirectory('/a');
      await settle();
      final b = remote.openDirectory('/b');
      final c = remote.openDirectory('/c');
      await settle();
      _dir(t.s, '/a', []);
      await a;
      await b;
      await settle();
      expect(_args(t.bind, #sessionReadRemoteDir, #path), ['/a', '/c']);

      // A job ends while /c is read: the refresh reads /c again, not the /a shown.
      unawaited(t.s.fileModel.onJobDone({'id': '999', 'file_num': '0'}));
      await settle();
      _dir(t.s, '/c', [_json('x')]);
      await c;
      await settle();
      expect(_args(t.bind, #sessionReadRemoteDir, #path), ['/a', '/c', '/c']);
      _dir(t.s, '/c', [_json('x')]);
      await settle();
      expect(remote.path, '/c');
      expect(remote.reading, isNull);
    });

    test('a remote read that gets no answer times out after 30 s', () {
      fakeAsync((async) {
        final t = _session();
        final remote = t.s.fileModel.remoteController;
        FtError? error;
        remote.openDirectory('/a').then((e) => error = e);
        async.flushMicrotasks();
        expect(remote.reading?.path, '/a');
        async.elapse(const Duration(seconds: 29));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(error?.reason, FtReason.timeout);
        expect(remote.openError?.path, '/a');
        expect(remote.reading, isNull);
      });
    });

    test('this device\'s folder failing keeps the folder shown and its reason; the path field '
        'gets the reason without a banner', () async {
      final t = _session();
      final local = t.s.fileModel.localController;
      t.api.onReadLocalDir = (path, hidden) => path == 'C:\\ok'
          ? (
              directory: FileDirectory.fromJson({
                'id': 0,
                'path': path,
                'entries': [_json('b.txt'), _json('A', type: 0)],
              }),
              error: null
            )
          : (directory: null, error: const FtError(FtReason.notFound));
      expect(await local.openDirectory('C:\\ok'), isNull);
      expect(local.entries.map((e) => e.path), ['C:\\ok\\A', 'C:\\ok\\b.txt']);
      local.select(local.entries);

      expect((await local.openDirectory('C:\\gone', showError: false))?.reason,
          FtReason.notFound);
      expect(local.openError, isNull);
      await local.openDirectory('C:\\gone');
      expect(local.path, 'C:\\ok');
      expect(local.openError?.error.reason, FtReason.notFound);
      expect(local.selection, hasLength(2));
      expect(_args(t.bind, #sessionPeerOption, #value), ['C:\\ok']);
    });

    test('the last folder is gone: the home folder opens and the banner says what was not '
        'found (02 §2.5)', () async {
      final t = _session();
      t.bind
        ..home = 'C:\\home'
        ..peerOptions['local_dir'] = 'C:\\gone';
      t.api.onReadLocalDir = (path, hidden) => path == 'C:\\home'
          ? (
              directory:
                  FileDirectory.fromJson({'id': 0, 'path': path, 'entries': []}),
              error: null
            )
          : (directory: null, error: const FtError(FtReason.notFound));
      final local = t.s.fileModel.localController;
      await local.onReady();
      expect(local.path, 'C:\\home');
      expect((local.openError?.path, local.openError?.error.reason),
          ('C:\\gone', FtReason.notFound));
    });

    test('a remote read the reconnect ends is no error to show', () async {
      final t = _session();
      final remote = t.s.fileModel.remoteController;
      final a = remote.openDirectory('/a');
      await settle();
      t.s.fileModel.fileFetcher.beginRemoteSession();
      expect(await a, isNull);
      expect(remote.openError, isNull);
    });

    test('"显示隐藏的项目" is saved at once, for the reconnect to read back', () async {
      final t = _session();
      t.s.fileModel.remoteController.setShowHidden(true);
      final saved = t.bind.callsTo(#sessionPeerOption).single.namedArguments;
      expect((saved[#name], saved[#value]), ('remote_show_hidden', 'Y'));
    });

    test('a whole drive dropped from the file manager is not sent', () async {
      final t = _session(platform: 'Windows');
      await t.s.fileModel
          .uploadPaths([p.rootPrefix(io.Directory.systemTemp.path)], to: 'D:\\x');
      expect(t.bind.callsTo(#sessionSendFiles), isEmpty);
      expect(t.s.fileModel.jobs.rows, isEmpty);
    });
  });

  group('new folder and rename', () {
    test('the answer to the request\'s own id comes back to the dialog', () async {
      final t = _session();
      t.api.onReason = (text, platform, side) =>
          FtError(FtReason.permissionDenied, text: '$side');
      final model = t.s.fileModel;
      final opened = model.remoteController.openDirectory('/home/u');
      await settle();
      _dir(t.s, '/home/u', [_json('Docs', type: 0)]);
      await opened;
      late FtNewFolderPrompt prompt;
      final closed = Completer<String?>();
      appCore.prompter = TestPrompter((q) {
        prompt = q as FtNewFolderPrompt;
        return closed.future;
      });
      final done = model.remoteController.newFolder();
      await settle();

      expect(prompt.isWindows, isFalse);
      expect(prompt.check('docs'), isNull, reason: 'names have case on Linux');
      expect(prompt.check('Docs'), FtNameError.alreadyExists);
      expect(prompt.check('a/b'), FtNameError.invalidChars);

      final failed = prompt.submit('x');
      await settle();
      final first = t.bind.callsTo(#sessionCreateDir).single.namedArguments;
      expect((first[#path], first[#isRemote]), ('/home/u/x', true));
      // Another request's error is not this one's.
      final id = first[#actId] as int;
      model.handleJobError({'id': '${id + 1}', 'err': 'other', 'file_num': '-1'});
      model.handleJobError({'id': '$id', 'err': 'denied', 'file_num': '-1'});
      expect((await failed)?.text, 'FtSide.remote');

      final made = prompt.submit('y');
      await settle();
      final second = t.bind.callsTo(#sessionCreateDir).last.namedArguments;
      // Not awaited: the refresh after it waits for a remote read nobody answers here.
      unawaited(model.onJobDone({'id': '${second[#actId]}', 'file_num': '-1'}));
      expect(await made, isNull);

      closed.complete('y');
      await done;
    });

    test('rename keeps the old name out of the check and sends the new one', () async {
      final t = _session(platform: 'Windows');
      final model = t.s.fileModel;
      t.api.onReadLocalDir = (path, hidden) => (
            directory: FileDirectory.fromJson({
              'id': 0,
              'path': path,
              'entries': [_json('a.txt'), _json('b.txt')],
            }),
            error: null
          );
      await model.localController.openDirectory('C:\\w');
      late FtRenamePrompt prompt;
      appCore.prompter = TestPrompter((q) {
        prompt = q as FtRenamePrompt;
        return null;
      });
      await model.localController.rename(model.localController.entries.first);

      expect(prompt.check('A.TXT'), isNull, reason: 'only the case changes');
      expect(prompt.check('B.txt'), FtNameError.alreadyExists);
      expect(prompt.check('a:b'), FtNameError.invalidChars);
      final renamed = prompt.submit('c.txt');
      await settle();
      final args = t.bind.callsTo(#sessionRenameFile).single.namedArguments;
      expect((args[#path], args[#newName], args[#isRemote]),
          ('C:\\w\\a.txt', 'c.txt', false));
      await model.onJobDone({'id': '${args[#actId]}', 'file_num': '-1'});
      expect(await renamed, isNull);
    });
  });

  group('delete (R2-Q23, M7a-3)', () {
    /// Plays Rust until [done]: counts from [dirs], each removal answered done.
    Future<void> drive(_Setup t, Future<void> done,
        Map<String, List<Map<String, dynamic>>> dirs) async {
      var finished = false;
      done.whenComplete(() => finished = true);
      var reads = 0, removes = 0, links = 0;
      for (var round = 0; !finished; round++) {
        expect(round, lessThan(50), reason: 'delete did not finish');
        await settle();
        final readCalls = t.bind.callsTo(#sessionReadDirToRemoveRecursive);
        for (; reads < readCalls.length; reads++) {
          final args = readCalls[reads].namedArguments;
          final path = args[#path] as String;
          _dir(t.s, path, dirs[path]!, id: args[#actId] as int);
        }
        final removeCalls = t.bind.callsTo(#sessionRemoveFile);
        for (; removes < removeCalls.length; removes++) {
          final args = removeCalls[removes].namedArguments;
          await t.s.fileModel
              .onJobDone({'id': '${args[#actId]}', 'file_num': '${args[#fileNum]}'});
        }
        for (; links < t.api.removedLinks.length; links++) {
          await t.s.fileModel.onJobDone(
              {'id': '${t.api.removedLinks[links].actId}', 'file_num': '0'});
        }
      }
      await done;
    }

    /// Answers [answer] once the confirmation shows what it is about.
    Future<bool?> whenReady(Prompt q, bool? answer) {
      final state = (q as FtDeletePrompt).state;
      final ready = Completer<bool?>();
      void check() {
        if (state.value is FtDeleteReady && !ready.isCompleted) {
          ready.complete(answer);
        }
      }

      state.addListener(check);
      check();
      return ready.future;
    }

    test('counts the folders, asks once, removes a link itself and the rest file by file',
        () async {
      final t = _session();
      final prompter = TestPrompter((q) => whenReady(q, true));
      appCore.prompter = prompter;
      final local = t.s.fileModel.localController;
      final items = [
        _entry('C:\\d1', type: 0),
        _entry('C:\\f.txt', size: 5),
        _entry('C:\\l', type: 2),
      ];

      await drive(t, local.delete(items), {
        'C:\\d1': [_json('a.txt', size: 2), _json('b.txt', size: 3)],
      });

      final prompt = prompter.asked.single as FtDeletePrompt;
      expect(prompt.isRemote, isFalse);
      final ready = prompt.state.value as FtDeleteReady;
      expect((ready.kind, ready.items, ready.files, ready.bytes),
          (FtDeleteKind.contents, 3, 3, 10));
      expect(_args(t.bind, #sessionReadDirToRemoveRecursive, #path), ['C:\\d1']);
      expect(_args(t.bind, #sessionRemoveFile, #path),
          ['C:\\d1\\a.txt', 'C:\\d1\\b.txt', 'C:\\f.txt']);
      expect(_args(t.bind, #sessionRemoveAllEmptyDirs, #path), ['C:\\d1']);
      final link = t.api.removedLinks.single;
      expect((link.path, link.isDirLink, link.isRemote), ('C:\\l', true, false));
      expect(t.s.fileModel.jobs.rows.map((r) => (r.direction, r.status)),
          everyElement((FileJobDirection.delete, FileJobStatus.done)));
      // Each row has the files the confirmation counted: the folder's two, the file, no file
      // for the link.
      expect(t.s.fileModel.jobs.rows.map((r) => (r.name, r.fileCount, r.totalBytes)),
          [('d1', 2, 5), ('f.txt', 1, 5), ('l', 0, 0)]);
    });

    test('cancelled while counting: nothing is deleted', () async {
      final t = _session();
      final prompter = TestPrompter((_) => null);
      appCore.prompter = prompter;
      final remote = t.s.fileModel.remoteController;

      await drive(t, remote.delete([_entry('/d', type: 0)]), {
        '/d': [_json('a.txt')],
      });

      expect((prompter.asked.single as FtDeletePrompt).isRemote, isTrue);
      expect(t.bind.callsTo(#sessionRemoveFile), isEmpty);
      expect(t.s.fileModel.jobs.rows, isEmpty);
    });

    test('a count that fails says why and can be retried', () async {
      final t = _session();
      t.api.onReason = (text, platform, side) =>
          FtError(FtReason.permissionDenied, text: '$side');
      final states = <FtDeleteState>[];
      appCore.prompter = TestPrompter((q) {
        final prompt = q as FtDeletePrompt;
        final answered = Completer<bool?>();
        prompt.state.addListener(() {
          states.add(prompt.state.value);
          if (prompt.state.value is FtDeleteCountFailed) prompt.retry();
          if (prompt.state.value is FtDeleteReady) answered.complete(null);
        });
        return answered.future;
      });
      final remote = t.s.fileModel.remoteController;
      final done = remote.delete([_entry('/d', type: 0)]);
      await settle();
      final first =
          t.bind.callsTo(#sessionReadDirToRemoveRecursive).single.namedArguments;
      t.s.fileModel
          .handleJobError({'id': '${first[#actId]}', 'err': 'denied', 'file_num': '-1'});
      await settle();
      final second =
          t.bind.callsTo(#sessionReadDirToRemoveRecursive).last.namedArguments;
      expect(second[#actId], isNot(first[#actId]));
      _dir(t.s, '/d', [], id: second[#actId] as int);
      await done;

      final failed = states.whereType<FtDeleteCountFailed>().single;
      expect((failed.folder, failed.error.text), ('d', 'FtSide.remote'));
      expect((states.last as FtDeleteReady).kind, FtDeleteKind.emptyFolder);
    });
  });

  group('close (models/model.dart:4375-4411 FFI.close, '
      'desktop/pages/file_manager_page.dart:125)', () {
    test('cleans up first and closes the Rust session last', () async {
      final fakes = installFakes();
      final s = appCore.sessions.open('100200300', ConnType.fileTransfer);

      await appCore.sessions.close(s);

      final names = fakes.bind.calls.map((c) => c.memberName).toList();
      expect(names.last, #sessionClose);
      // FileModel.close saves the directories it showed.
      expect(names.indexOf(#sessionPeerOption), lessThan(names.indexOf(#sessionClose)));
    });

    test('closes the Rust session when the cleanup throws', () async {
      final fakes = installFakes();
      final s = appCore.sessions.open('100200300', ConnType.fileTransfer);
      fakes.bind.failing.add(#sessionPeerOption);

      await expectLater(appCore.sessions.close(s), throwsStateError);

      expect(fakes.bind.callsTo(#sessionClose), hasLength(1));
    });
  });

  test('a file transfer session is its own file transfer model', () {
    installFakes();
    final s = appCore.sessions.open('100200300', ConnType.fileTransfer);
    expect(fileTransferOf(s), same(s.fileModel));
    expect(s.fileModel, isA<FileModel>());
  });
}
