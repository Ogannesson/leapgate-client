import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'app_core.dart';
import 'notices.dart';
import 'session.dart';

// Tags of the session notices the app puts buttons on (01 P2 block E). Each notice of one kind
// replaces the one before it.
const kNoticeTagScreenshot = 'screenshot';
const kNoticeTagScreenshotFailed = 'screenshot-failed';
const kNoticeTagAutoRecord = 'auto-record';
const kNoticeTagPrivacySwitchDisplay = 'privacy-switch-display';

/// The tag of a print job notice: one per job.
const kNoticeTagPrinterPrefix = 'printer-';

/// The tag of a revoked permission notice, before the permission's name.
const kNoticeTagPermissionPrefix = 'permission-';

/// Keys of the notices that have no upstream text.
const kNoticeAutoRecording = 'leapgate-auto-recording';
const kNoticePermissionRevoked = 'leapgate-permission-revoked';

/// The permissions whose loss during a session gets a notice (Rust's `set_permission` names,
/// `src/client/io_loop.rs`).
const kRevocablePermissions = [
  'keyboard',
  'clipboard',
  'audio',
  'file',
  'restart',
  'recording',
  'block_input',
  'privacy_mode',
];

/// Upstream's screenshot cool-down (`common/widgets/toolbar.dart:769`).
const kScreenshotCooldown = Duration(seconds: 30);

/// What a session asks the user about and tells without a dialog (01 P2 block E): the screenshot,
/// a print job, switching sides back, a permission taken away during the session, a recording
/// started by itself. Upstream showed most of these as dialogs (`models/model.dart:407-410`,
/// `:484-722`); here each is a notice, and the app puts the buttons on it by its tag.
class SessionRequests {
  SessionRequests(this.parent) {
    final ffi = parent.target!;
    ffi.ffiModel.addListener(_onPermissions);
    ffi.recordingModel.addListener(_onRecording);
  }

  final WeakReference<FFI> parent;

  FFI get _ffi => parent.target!;
  SessionNotices get _notices => _ffi.notices;

  // Screenshot.

  Timer? _screenshotTimer;
  final _screenshotPending = ValueNotifier(false);

  /// "正在截图…" in the actions menu: from asking until Rust answers, at most
  /// [kScreenshotCooldown] (upstream `FfiModel.timerScreenshot`).
  ValueListenable<bool> get screenshotPending => _screenshotPending;

  /// Upstream's "Take screenshot" (`common/widgets/toolbar.dart:748-772`); does nothing during the
  /// cool-down, so a shortcut held on to the menu's callback cannot ask twice.
  void takeScreenshot() {
    if (_screenshotPending.value) return;
    final pi = _ffi.ffiModel.pi;
    if (pi.currentDisplay == kAllDisplayValue) {
      _screenshotFailed('screenshot-merged-screen-not-supported-tip');
      return;
    }
    bind.sessionTakeScreenshot(
        sessionId: _ffi.sessionId, display: pi.currentDisplay);
    _screenshotPending.value = true;
    _screenshotTimer = Timer(kScreenshotCooldown, _endScreenshotWait);
  }

  void _endScreenshotWait() {
    _screenshotTimer?.cancel();
    _screenshotTimer = null;
    _screenshotPending.value = false;
  }

  /// The `screenshot` event (upstream `_handleScreenshot`): Rust holds the image until one of the
  /// three answers.
  void onScreenshot(Map<String, dynamic> evt) {
    _endScreenshotWait();
    final msg = '${evt['msg'] ?? ''}';
    if (msg.isNotEmpty) {
      _screenshotFailed(msg);
    } else {
      _notices.add(
          SessionNotice('screenshot-action-tip', tag: kNoticeTagScreenshot));
    }
  }

  void _screenshotFailed(String text) => _notices.add(SessionNotice(text,
      args: const {'title': 'Take screenshot'},
      tag: kNoticeTagScreenshotFailed));

  /// "另存为" with the path the user chose, null when the file dialog was cancelled.
  Future<void> saveScreenshot(String? path) async {
    _notices.dismissTag(kNoticeTagScreenshot);
    if (path == null) {
      await bind.sessionHandleScreenshot(
          sessionId: _ffi.sessionId, action: '2');
      return;
    }
    final res = await bind.sessionHandleScreenshot(
        sessionId: _ffi.sessionId, action: '0:$path');
    if (res.isNotEmpty) _screenshotFailed(res);
  }

  /// "复制到剪贴板".
  Future<void> copyScreenshot() async {
    _notices.dismissTag(kNoticeTagScreenshot);
    await bind.sessionHandleScreenshot(sessionId: _ffi.sessionId, action: '1');
  }

  /// The notice closed without an answer: Rust drops the image.
  Future<void> discardScreenshot() async {
    _notices.dismissTag(kNoticeTagScreenshot);
    await bind.sessionHandleScreenshot(sessionId: _ffi.sessionId, action: '2');
  }

  // Print job.

  /// The `printer_request` event: Rust asks only when the incoming job is neither dismissed nor
  /// printed by itself (`src/client/io_loop.rs:2287-2312`).
  void onPrinterRequest(Map<String, dynamic> evt) {
    _notices.add(SessionNotice('print-incoming-job-confirm-tip',
        tag: '$kNoticeTagPrinterPrefix${evt['id']}',
        args: {'id': '${evt['id']}', 'path': '${evt['path'] ?? ''}'}));
  }

  /// The printers to choose from (upstream `PrinterOptions.load`), and the one chosen last.
  ({List<String> names, String selected}) printers() => (
        names: getPrinterNames(),
        selected: appCore.options.local.get(kKeyPrinterSelected),
      );

  /// Answers a print job notice: with the default printer ([printer] ''), with [printer], or not
  /// at all ([print] false). [remember] saves the answer for the next jobs, as upstream's
  /// "Don't show again" (`models/model.dart:567-590`): printing ones print by themselves after.
  Future<void> answerPrintJob(SessionNotice notice,
      {bool print = true, String printer = '', bool remember = false}) async {
    _notices.dismiss(notice);
    final local = appCore.options.local;
    if (!print) {
      if (remember) {
        await local.set(
            kKeyPrinterIncomingJobAction, kValuePrinterIncomingJobDismiss);
      }
      return;
    }
    await bind.sessionPrinterResponse(
        sessionId: _ffi.sessionId,
        id: int.parse(notice.args['id']!),
        path: notice.args['path']!,
        printerName: printer);
    if (remember) {
      await local.set(kKeyPrinterSelected, printer);
      await local.set(
          kKeyPrinterIncomingJobAction,
          printer.isEmpty
              ? kValuePrinterIncomingJobDefault
              : kValuePrinterIncomingJobSelected);
      await local.setBool(kKeyPrinterAllowAutoPrint, true);
    }
  }

  // Switching sides back.

  /// The `switch_back` event (upstream `models/model.dart:407-410`): the remote side asked to
  /// switch back; this session ends.
  Future<void> onSwitchBack(Map<String, dynamic> evt) async {
    await bind.sessionSwitchSides(sessionId: _ffi.sessionId);
    await appCore.sessions.closeDevice('${evt['peer_id']}');
  }

  // Privacy mode.

  /// Privacy mode turns on only on the first monitor where the implementation cannot switch
  /// (upstream `common/widgets/toolbar.dart:1239-1249`); the toolbar asks here instead of turning
  /// it on.
  void showSwitchToFirstMonitor() =>
      _notices.add(SessionNotice('Please switch to Display 1 first',
          tag: kNoticeTagPrivacySwitchDisplay));

  /// "切换到显示器 1".
  void switchToFirstMonitor() {
    _notices.dismissTag(kNoticeTagPrivacySwitchDisplay);
    openMonitorInTheSameTab(0, _ffi, _ffi.ffiModel.pi);
  }

  // Permissions taken away.

  var _permissions = <String, bool>{};

  /// A permission that was given and is now taken away gets a notice (01 P2 block B); one given
  /// again takes its notice away.
  void _onPermissions() {
    final now = Map.of(_ffi.ffiModel.permissions);
    for (final p in kRevocablePermissions) {
      if (_permissions[p] == true && now[p] == false) {
        _notices.add(SessionNotice(kNoticePermissionRevoked,
            args: {'permission': p}, tag: '$kNoticeTagPermissionPrefix$p'));
      } else if (_permissions[p] == false && now[p] == true) {
        _notices.dismissTag('$kNoticeTagPermissionPrefix$p');
      }
    }
    _permissions = now;
  }

  // Recording.

  var _recording = false;
  var _userToggledRecording = false;

  /// The record button: starts or stops the recording.
  Future<void> toggleRecording() {
    _userToggledRecording = true;
    return _ffi.recordingModel.toggle();
  }

  /// A recording this side started by itself ("自动录制传出会话", Rust starts it with the
  /// first video, `src/client/io_loop.rs:2720-2724`) gets a notice with "停止" once.
  void _onRecording() {
    final start = _ffi.recordingModel.start;
    if (start == _recording) return;
    _recording = start;
    if (!start) {
      _notices.dismissTag(kNoticeTagAutoRecord);
    } else if (!_userToggledRecording &&
        appCore.options.local.get(kOptionAllowAutoRecordOutgoing) == 'Y') {
      _userToggledRecording = true;
      _notices
          .add(SessionNotice(kNoticeAutoRecording, tag: kNoticeTagAutoRecord));
    }
  }
}
