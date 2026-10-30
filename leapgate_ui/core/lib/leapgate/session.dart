// 上游：flutter/lib/models/model.dart@bd9262397（改写：`ConnType` 和会话对象 `FFI`。上游这两段改了，合并时人工移植到这里）
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/desktop_render_texture.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import 'app_core.dart';
import 'notices.dart';
import 'options.dart';
import 'prompts.dart';
import 'session_events.dart';

/// `index` goes to Rust as the connection type (upstream `FfiModel`), so the order stays
/// upstream's. A session tab shows `defaultConn` (remote desktop) and `fileTransfer`; camera and
/// terminal come in round 3.
enum ConnType {
  defaultConn,
  fileTransfer,
  portForward,
  rdp,
  viewCamera,
  terminal
}

/// One session: one view of one device (03 §3.3 item 1). Keeps upstream's class and member
/// names, so the copied models reach it through `WeakReference<FFI>` unchanged. Only
/// [SessionRegistry] creates, starts and closes it.
///
/// Unlike upstream, it holds only the session's own models; the global ones are on [AppCore].
class FFI {
  FFI(this.id, this.connType) : sessionId = const Uuid().v4obj() {
    options = SessionOptions(sessionId);
    imageModel = ImageModel(WeakReference(this));
    ffiModel = FfiModel(WeakReference(this));
    cursorModel = CursorModel(WeakReference(this));
    canvasModel = CanvasModel(WeakReference(this));
    fileModel = FileModel(WeakReference(this));
    qualityMonitorModel = QualityMonitorModel(WeakReference(this));
    recordingModel = RecordingModel(WeakReference(this));
    inputModel = InputModel(WeakReference(this));
    elevationModel = ElevationModel(WeakReference(this));
    textureModel = TextureModel(WeakReference(this));
    _registerEvents();
  }

  /// The events of the copied models (upstream `FfiModel.startEventListener`,
  /// `models/model.dart:370-391`, `:396-397`, `:460-465`). Upstream handles `record_status`
  /// only in a session window; here every session is in one.
  void _registerEvents() {
    events.on('file_dir', (evt) => fileModel.receiveFileDir(evt));
    events.on('empty_dirs', (evt) => fileModel.receiveEmptyDirs(evt));
    events.on('job_progress',
        (evt) => fileModel.jobController.tryUpdateJobProgress(evt));
    events.on('job_done', (evt) async {
      bool? refresh = await fileModel.jobController.jobDone(evt);
      if (refresh == true) {
        // many job done for delete directory
        // todo: refresh may not work when confirm delete local directory
        fileModel.refreshAll();
      }
    });
    events.on('job_error', (evt) => fileModel.handleJobError(evt));
    events.on('override_file_confirm',
        (evt) => fileModel.postOverrideFileConfirm(evt));
    events.on(
        'load_last_job', (evt) => fileModel.jobController.loadLastJob(evt));
    events.on('update_folder_files',
        (evt) => fileModel.jobController.updateFolderFiles(evt));
    events.on('update_quality_status',
        (evt) => qualityMonitorModel.updateQualityStatus(evt));
    events.on('record_status',
        (evt) => recordingModel.updateStatus(evt['start'] == 'true'));
  }

  final SessionID sessionId;

  late final SessionOptions options;
  late final ImageModel imageModel;
  late final FfiModel ffiModel;
  late final CursorModel cursorModel;
  late final CanvasModel canvasModel;
  late final FileModel fileModel;
  late final QualityMonitorModel qualityMonitorModel;
  late final RecordingModel recordingModel;
  late final InputModel inputModel;
  late final ElevationModel elevationModel;
  late final TextureModel textureModel;

  /// The device ID.
  final String id;

  final ConnType connType;

  /// Set by [close] and by Rust's `close` event.
  var closed = false;

  final events = SessionEvents();
  final notices = SessionNotices();

  // State upstream kept per device ID in GetX registries (`common/shared_state.dart`): two views
  // of one device in one engine would share it, and closing one would delete the other's.
  // Upstream class in each comment; initial values are upstream's.
  final keyboardEnabled = true.obs; // KeyboardEnabledState
  final currentDisplay = 0.obs; // CurrentDisplayState
  final privacyMode = ''.obs; // PrivacyModeState
  final blockInput = false.obs; // BlockInputState
  final fingerprint = ''.obs; // FingerprintState
  final showRemoteCursor = false.obs; // ShowRemoteCursorState
  final remoteCursorMoved = false.obs; // RemoteCursorMovedState

  /// The token that lets another view of this device log in without the password again
  /// (upstream `common/widgets/toolbar.dart:580`).
  String? get connToken => bind.sessionGetConnToken(sessionId: sessionId);

  /// Asks the user over this session's tab.
  Future<T?> ask<T>(Prompt<T> prompt) =>
      appCore.prompter.ask(prompt, session: this);

  bool get _hasImage =>
      connType == ConnType.defaultConn || connType == ConnType.viewCamera;

  /// Upstream `FFI.start` without the tab-to-window path, plus the model setup upstream's pages
  /// did around it (`desktop/pages/remote_page.dart:160-165`, `:198`,
  /// `desktop/pages/view_camera_page.dart:105-110`, `:130`).
  void start({bool forceRelay = false, String? connToken}) {
    if (connType == ConnType.defaultConn) {
      canvasModel.id = id;
      imageModel.id = id;
      cursorModel.peerId = id;
    }
    if (_hasImage) {
      imageModel.addCallbackOnFirstImage((String peerId) {
        if (connType == ConnType.defaultConn) {
          canvasModel.activateLocalCursor();
        }
        recordingModel
            .updateStatus(bind.sessionGetIsRecording(sessionId: sessionId));
      });
    }
    bind.sessionAddSync(
      sessionId: sessionId,
      id: id,
      isFileTransfer: connType == ConnType.fileTransfer,
      isViewCamera: connType == ConnType.viewCamera,
      // Upstream starts RDP as a port forward with isRdp set.
      isPortForward:
          connType == ConnType.portForward || connType == ConnType.rdp,
      isRdp: connType == ConnType.rdp,
      isTerminal: connType == ConnType.terminal,
      switchUuid: '',
      forceRelay: forceRelay,
      password: '',
      isSharedPassword: false,
      connToken: connToken,
    );
    if (isDesktop && _hasImage) {
      textureModel.updateCurrentDisplay(0);
    }

    if (isDesktop) {
      inputModel.updateTrackpadSpeed();
    }

    imageModel.updateUserTextureRender();
    _hasGpuTextureRender = bind.mainHasGpuTextureRender();
    // Like upstream, messages are not awaited one after another.
    bind.sessionStart(sessionId: sessionId, id: id).listen((message) {
      if (closed) return;
      _onMessage(message);
    });
    if (_hasImage) {
      qualityMonitorModel.checkShowQualityMonitor(sessionId);
    }
  }

  var _hasGpuTextureRender = false;

  Future<void> _onMessage(EventToUI message) async {
    if (message is EventToUI_Event) {
      if (message.field0 == 'close') {
        closed = true;
        return;
      }
      await events.dispatch(json.decode(message.field0));
    } else if (message is EventToUI_Rgba) {
      final display = message.field0;
      // Fetch the image buffer from rust codes.
      final sz = platformFFI.getRgbaSize(sessionId, display);
      if (sz == 0) {
        platformFFI.nextRgba(sessionId, display);
        return;
      }
      final rgba = platformFFI.getRgba(sessionId, display, sz);
      if (rgba != null) {
        onEvent2UIRgba();
        await imageModel.onRgba(display, rgba);
      } else {
        platformFFI.nextRgba(sessionId, display);
      }
    } else if (message is EventToUI_Cursor) {
      await ffiModel.handleCursorData(message.id, message.hotx, message.hoty,
          message.width, message.height, message.colors);
    } else if (message is EventToUI_Texture) {
      final display = message.field0;
      final gpuTexture = message.field1;
      debugPrint("EventToUI_Texture display:$display, gpuTexture:$gpuTexture");
      if (gpuTexture && !_hasGpuTextureRender) {
        debugPrint('the gpuTexture is not supported.');
        return;
      }
      textureModel.setTextureType(display: display, gpuTexture: gpuTexture);
      onEvent2UIRgba();
    }
  }

  /// Upstream `FFI.onEvent2UIRgba` without the waiting-for-image dialog (`model.dart:4322-4326`)
  /// and the reset of the restart reconnect (`:4330`), which are the connection state's.
  Future<void> onEvent2UIRgba() async {
    if (ffiModel.waitForFirstImage.value == true) {
      ffiModel.waitForFirstImage.value = false;
      ffiModel.cancelPendingRestoreTimer();
      try {
        await canvasModel.updateViewStyle();
        await canvasModel.updateScrollStyle();
        await canvasModel.initializeEdgeScrollEdgeThickness();
        for (final cb in imageModel.callbacksOnFirstImage) {
          cb(id);
        }
      } finally {
        applyPendingMonitorRestore();
      }
    }
  }

  void applyPendingMonitorRestore() {
    final restore = ffiModel.pendingMonitorRestore;
    ffiModel.cancelPendingMonitorRestore();
    if (restore == null || closed) return;
    // The display list may have changed since the restore was queued.
    final displays = ffiModel.pi.displays;
    if ((restore == kAllDisplayValue && displays.isNotEmpty) ||
        (restore >= 0 && restore < displays.length)) {
      openMonitorInTheSameTab(restore, this, ffiModel.pi,
          recordSelection: false, updateCursorPos: false);
    }
  }

  /// Upstream `FFI.close`, plus the model cleanup upstream's pages did before it, now that the
  /// pages no longer close sessions: `FileModel.close` (`desktop/pages/file_manager_page.dart:125`)
  /// and the textures and images of the remote page (`desktop/pages/remote_page.dart:676`,
  /// `:684-685`). The textures are made in [start], so they go with the session, not the page.
  /// Rust closes the session even when the cleanup throws, as upstream's file page closes it
  /// whatever `FileModel.close` does (`model.close().whenComplete(() => _ffi.close())`).
  Future<void> close() async {
    closed = true;
    try {
      if (connType == ConnType.fileTransfer) {
        await fileModel.close();
      }
      if (connType == ConnType.defaultConn) {
        textureModel.onRemotePageDispose(true);
      } else if (connType == ConnType.viewCamera) {
        textureModel.onViewCameraPageDispose(true);
      }
      imageModel.disposeImage();
      cursorModel.disposeImages();
      // Never true after disposeImage: upstream's desktop pages dispose the image before
      // FFI.close too, so the desktop does not save the canvas position (only the web reads it).
      if (imageModel.image != null && !isWebDesktop) {
        await setCanvasConfig(sessionId, cursorModel.x, cursorModel.y,
            canvasModel.x, canvasModel.y, canvasModel.scale,
            ffiModel.pi.currentDisplay);
      }
      imageModel.callbacksOnFirstImage.clear();
      await imageModel.update(null);
      cursorModel.clear();
      ffiModel.clear();
      canvasModel.clear();
      inputModel.resetModifiers();
      // Dispose relative mouse mode resources to ensure cursor is restored
      inputModel.disposeRelativeMouseMode();
      inputModel.disposeSideButtonTracking();
    } finally {
      await bind.sessionClose(sessionId: sessionId);
    }
  }
}
