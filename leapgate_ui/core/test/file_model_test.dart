import 'dart:convert';

import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/prompts.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

// The file transfer flows whose questions moved from upstream's dialogs to the prompter
// (03 §3.4 "文件传输的续传、替换确认的流程"). Test names give the upstream place
// (flutter/lib/models/file_model.dart@bd9262397).

/// Answers the questions in order and keeps them.
class ScriptedPrompter implements Prompter {
  ScriptedPrompter(this.answers);

  final List<Object?> answers;
  final asked = <Prompt>[];

  @override
  Future<T?> ask<T>(Prompt<T> prompt, {FFI? session}) async {
    asked.add(prompt);
    return answers.removeAt(0) as T?;
  }
}

Map<String, dynamic> _file(String name) =>
    {'entry_type': 4, 'modified_time': 0, 'name': name, 'size': 1};

Entry _dir(String name) => Entry()
  ..entryType = 1
  ..name = name
  ..path = '/$name';

void main() {
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
        final fakes = installFakes();
        final prompter = ScriptedPrompter([answer]);
        appCore.prompter = prompter;
        final s = appCore.sessions.open('100200300', ConnType.fileTransfer);
        final jobs = s.fileModel.jobController;
        final id = jobs.addTransferJob(Entry()..path = '/a.txt', false);
        jobs.registerTransferConflictBatch([id]);

        await s.fileModel.overrideFileConfirm({
          'id': '$id',
          'file_num': '0',
          'read_path': '/a.txt',
          'is_identical': 'false',
          'is_upload': 'true',
        });

        expect((prompter.asked.single as OverwritePrompt).path, '/a.txt');
        final sent = fakes.bind.callsTo(#sessionSetConfirmOverrideFile);
        final cancelled = fakes.bind.callsTo(#sessionCancelJob);
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

  group('delete (file_model.dart:738-856 removeAction)', () {
    /// Runs [removal], answering Rust's side: each recursive read of a directory in [dirs] with
    /// its files, each file removal with its `job_done`.
    Future<void> drive(FakeBind bind, FFI s, Future<void> removal,
        Map<String, List<String>> dirs) async {
      final stream = bind.streams[s.sessionId]!;
      var finished = false;
      removal.whenComplete(() => finished = true);
      var reads = 0, removes = 0;
      for (var round = 0; !finished; round++) {
        expect(round, lessThan(50), reason: 'removeAction did not finish');
        await settle();
        final readCalls = bind.callsTo(#sessionReadDirToRemoveRecursive);
        for (; reads < readCalls.length; reads++) {
          final args = readCalls[reads].namedArguments;
          final path = args[#path] as String;
          stream.add(EventToUI.event(jsonEncode({
            'name': 'file_dir',
            'is_local': 'true',
            'value': jsonEncode({
              'id': args[#actId],
              'path': path,
              'entries': dirs[path]!.map(_file).toList(),
            }),
          })));
        }
        final removeCalls = bind.callsTo(#sessionRemoveFile);
        for (; removes < removeCalls.length; removes++) {
          final args = removeCalls[removes].namedArguments;
          stream.add(EventToUI.event(jsonEncode({
            'name': 'job_done',
            'id': '${args[#actId]}',
            'file_num': '${args[#fileNum]}',
          })));
        }
      }
      await removal;
    }

    List<DeletePrompt> asked(ScriptedPrompter p) =>
        p.asked.cast<DeletePrompt>().toList();

    test('"for all" with cancel skips the rest of the directory; the next directory starts '
        'with the box ticked (:832-848, :897)', () async {
      final fakes = installFakes();
      final prompter = ScriptedPrompter([
        (delete: false, forAll: true),
        (delete: false, forAll: false),
        (delete: false, forAll: false),
      ]);
      appCore.prompter = prompter;
      final s = appCore.sessions.open('100200300', ConnType.fileTransfer);
      final items = SelectedItems(isLocal: true)
        ..add(_dir('d1'))
        ..add(_dir('d2'));

      await drive(fakes.bind, s, s.fileModel.localController.removeAction(items), {
        '/d1': ['a', 'b'],
        '/d2': ['c', 'd'],
      });

      final prompts = asked(prompter);
      expect(prompts.map((p) => p.path.split('/').last), ['a', 'c', 'd']);
      expect(prompts.map((p) => p.kind), everyElement(DeleteKind.fileInDirectory));
      expect(prompts.map((p) => p.forAll), [false, true, false]);
      expect(prompts.map((p) => (p.index, p.count)), [(0, 2), (0, 2), (1, 2)]);
      expect(fakes.bind.callsTo(#sessionRemoveFile), isEmpty);
    });

    test('"for all" with delete removes the rest of the directory without asking, then the '
        'directory (:820-841)', () async {
      final fakes = installFakes();
      final prompter = ScriptedPrompter([(delete: true, forAll: true)]);
      appCore.prompter = prompter;
      final s = appCore.sessions.open('100200300', ConnType.fileTransfer);
      final items = SelectedItems(isLocal: true)..add(_dir('d1'));

      await drive(fakes.bind, s, s.fileModel.localController.removeAction(items), {
        '/d1': ['a', 'b', 'c'],
      });

      expect(asked(prompter), hasLength(1));
      expect(
          fakes.bind
              .callsTo(#sessionRemoveFile)
              .map((c) => (c.namedArguments[#path] as String).split('/').last),
          ['a', 'b', 'c']);
      expect(fakes.bind.callsTo(#sessionRemoveAllEmptyDirs).single.namedArguments[#path],
          '/d1');
    });
  });

  test('rename checks the new name and renames on an answer (file_model.dart:952-1021 '
      'renameAction)', () async {
    final fakes = installFakes();
    final prompter = ScriptedPrompter(['c.txt', 'a.txt']);
    appCore.prompter = prompter;
    final s = appCore.sessions.open('100200300', ConnType.fileTransfer);
    final files = s.fileModel.localController;
    files.directory.value = FileDirectory()
      ..entries = [Entry()..name = 'b.txt'];
    files.options.value.isWindows = true;
    final item = Entry()
      ..name = 'a.txt'
      ..path = 'C:\\a.txt';

    await files.renameAction(item, true);
    final check = (prompter.asked.single as RenamePrompt).check;
    expect(check('b.txt'), RenameError.alreadyExists);
    expect(check('a:b.txt'), RenameError.invalidName);
    expect(check('a.txt'), isNull);
    expect(check(''), isNull);
    expect(check('c.txt'), isNull);
    final args = fakes.bind.callsTo(#sessionRenameFile).single.namedArguments;
    expect((args[#path], args[#newName], args[#isRemote]),
        ('C:\\a.txt', 'c.txt', false));

    // The unchanged name renames nothing.
    await files.renameAction(item, true);
    expect(fakes.bind.callsTo(#sessionRenameFile), hasLength(1));
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
}
