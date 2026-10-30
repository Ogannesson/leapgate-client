// 上游：flutter/lib/models/model.dart@bd9262397 的 FfiModel（改写：只做 peer info、显示器、权限、光标、隐私模式等非连接部分，事件经 ffi.events 登记；连接状态那部分归 lib/leapgate/connection.dart。上游这一段改了，合并时人工移植到这里）
//
// A part of models/model.dart, as upstream's FfiModel was: it sets `Display._scale`.
part of '../models/model.dart';

class FfiModel with ChangeNotifier {
  PeerInfo _pi = PeerInfo();
  int? lastUserDisplay;
  int? pendingMonitorRestore;
  Timer? _pendingRestoreTimer;
  Rect? _rect;

  var _inputBlocked = false;
  final _permissions = <String, bool>{};
  bool _touchMode = false;
  bool _viewOnly = false;
  bool _showMyCursor = false;
  WeakReference<FFI> parent;
  late final SessionID sessionId;

  /// Set back to true whenever the session waits for a new first frame (peer info, a texture
  /// render switch); the first frame then runs [FFI.onEvent2UIRgba]'s first-image work.
  RxBool waitForFirstImage = true.obs;

  /// The wait for the first frame follows a texture render switch, not a new connection.
  bool isRefreshing = false;

  Rect? get rect => _rect;
  bool get isOriginalResolutionSet =>
      _pi.tryGetDisplayIfNotAllDisplay()?.isOriginalResolutionSet ?? false;
  bool get isVirtualDisplayResolution =>
      _pi.tryGetDisplayIfNotAllDisplay()?.isVirtualDisplayResolution ?? false;
  bool get isOriginalResolution =>
      _pi.tryGetDisplayIfNotAllDisplay()?.isOriginalResolution ?? false;

  Map<String, bool> get permissions => _permissions;
  setPermissions(Map<String, bool> permissions) {
    _permissions.clear();
    _permissions.addAll(permissions);
  }

  PeerInfo get pi => _pi;

  bool get inputBlocked => _inputBlocked;

  bool get touchMode => _touchMode;

  bool get isPeerAndroid => _pi.platform == kPeerPlatformAndroid;
  bool get isPeerMobile => isPeerAndroid;

  bool get isPeerLinux => _pi.platform == kPeerPlatformLinux;
  bool get isPeerWindows => _pi.platform == kPeerPlatformWindows;

  bool get viewOnly => _viewOnly;
  bool get showMyCursor => _showMyCursor;

  set inputBlocked(v) {
    _inputBlocked = v;
  }

  FfiModel(this.parent) {
    clear();
    sessionId = parent.target!.sessionId;
    _registerEvents(parent.target!);
  }

  /// Upstream `startEventListener` (`models/model.dart:331-482`), the branches that are not
  /// the connection state's. The models copied from upstream register theirs in [FFI]'s
  /// constructor.
  void _registerEvents(FFI ffi) {
    final peerId = ffi.id;
    final events = ffi.events;
    events.on('peer_info', (evt) => handlePeerInfo(evt, peerId, false));
    events.on('sync_peer_info',
        (evt) => handleSyncPeerInfo(evt, sessionId, peerId));
    events.on('sync_platform_additions',
        (evt) => handlePlatformAdditions(evt, sessionId, peerId));
    // switch display is kept for backward compatibility
    events.on('switch_display',
        (evt) => handleSwitchDisplay(evt, sessionId, peerId));
    events.on('cursor_id', (evt) {
      updateLastCursorId(evt);
      handleCursorId(evt);
    });
    events.on('cursor_position', (evt) async {
      await parent.target?.cursorModel.updateCursorPosition(evt, peerId);
    });
    events.on('clipboard', (evt) {
      Clipboard.setData(ClipboardData(text: evt['content']));
    });
    events.on('permission', (evt) => updatePermission(evt, peerId));
    events.on('update_block_input_state',
        (evt) => updateBlockInputState(evt, peerId));
    events.on('update_privacy_mode',
        (evt) => updatePrivacyMode(evt, sessionId, peerId));
    events.on('portable_service_running',
        (evt) => _handlePortableServiceRunning(peerId, evt));
    events.on('fingerprint', (evt) {
      parent.target?.fingerprint.value = evt['fingerprint'] ?? '';
    });
    events.on('sync_peer_option', (evt) => _handleSyncPeerOption(evt, peerId));
    events.on('follow_current_display',
        (evt) => handleFollowCurrentDisplay(evt, sessionId, peerId));
    events.on('use_texture_render',
        (evt) => _handleUseTextureRender(evt, sessionId, peerId));
    events.on('exit_relative_mouse_mode', (evt) {
      // Handle exit shortcut from rdev grab loop (Ctrl+Alt on Win/Linux, Cmd+G on macOS)
      parent.target?.inputModel.exitRelativeMouseModeWithKeyRelease();
    });
  }

  Rect? globalDisplaysRect() => _getDisplaysRect(_pi.displays, true);
  Rect? displaysRect() => _getDisplaysRect(_pi.getCurDisplays(), false);
  Rect? _getDisplaysRect(List<Display> displays, bool useDisplayScale) {
    if (displays.isEmpty) {
      return null;
    }
    if (isPeerLinux) {
      useDisplayScale = true;
    }
    int scale(int len, double s) {
      if (useDisplayScale) {
        return len.toDouble() ~/ s;
      } else {
        return len;
      }
    }

    double l = displays[0].x;
    double t = displays[0].y;
    double r = displays[0].x + scale(displays[0].width, displays[0].scale);
    double b = displays[0].y + scale(displays[0].height, displays[0].scale);
    for (var display in displays.sublist(1)) {
      l = min(l, display.x);
      t = min(t, display.y);
      r = max(r, display.x + scale(display.width, display.scale));
      b = max(b, display.y + scale(display.height, display.scale));
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  toggleTouchMode() {
    if (!isPeerAndroid) {
      _touchMode = !_touchMode;
      notifyListeners();
    }
  }

  updatePermission(Map<String, dynamic> evt, String id) {
    // Track previous keyboard permission to detect revocation.
    final hadKeyboardPerm = _permissions['keyboard'] != false;

    evt.forEach((k, v) {
      if (k == 'name' || k.isEmpty) return;
      _permissions[k] = v == 'true';
    });
    // Only inited at remote page
    if (parent.target?.connType == ConnType.defaultConn) {
      parent.target!.keyboardEnabled.value = _permissions['keyboard'] != false;
    }

    // If keyboard permission was revoked while relative mouse mode is active,
    // forcefully disable relative mouse mode to prevent the user from being trapped.
    final hasKeyboardPerm = _permissions['keyboard'] != false;
    if (hadKeyboardPerm && !hasKeyboardPerm) {
      final inputModel = parent.target?.inputModel;
      if (inputModel != null && inputModel.relativeMouseMode.value) {
        inputModel.setRelativeMouseMode(false);
        appCore.toasts.show('rel-mouse-permission-lost-tip');
      }
    }

    debugPrint('updatePermission: $_permissions');
    notifyListeners();
  }

  bool get keyboard => _permissions['keyboard'] != false;

  /// Upstream also resets the connection state here (`models/model.dart:254-264`); that is
  /// [ConnectionModel.clear], called next to this one.
  clear() {
    _pi = PeerInfo();
    lastUserDisplay = null;
    cancelPendingMonitorRestore();
    _inputBlocked = false;
    clearPermissions();
  }

  clearPermissions() {
    _inputBlocked = false;
    _permissions.clear();
  }

  _handleUseTextureRender(
      Map<String, dynamic> evt, SessionID sessionId, String peerId) {
    parent.target?.imageModel.setUseTextureRender(evt['v'] == 'Y');
    waitForFirstImage.value = true;
    isRefreshing = true;
    parent.target?.connection.showConnectedWaitingForImage();
  }

  _handleSyncPeerOption(Map<String, dynamic> evt, String peer) {
    final k = evt['k'];
    final v = evt['v'];
    if (k == kOptionToggleViewOnly) {
      setViewOnly(peer, v as bool);
    } else if (k == 'keyboard_mode') {
      parent.target?.inputModel.updateKeyboardMode();
    } else if (k == 'input_source') {
      stateGlobal.getInputSource(force: true);
    }
  }

  _handlePortableServiceRunning(String peerId, Map<String, dynamic> evt) {
    final running = evt['running'] == 'true';
    parent.target?.elevationModel.onPortableServiceRunning(running);
  }

  Future<void> updateCurDisplay(SessionID sessionId,
      {updateCursorPos = false}) async {
    final newRect = displaysRect();
    if (newRect == null) {
      return;
    }
    if (newRect != _rect) {
      if (newRect.left != _rect?.left || newRect.top != _rect?.top) {
        parent.target?.cursorModel.updateDisplayOrigin(
            newRect.left, newRect.top,
            updateCursorPos: updateCursorPos);
      }
      _rect = newRect;
      // Await updateViewStyle to ensure view geometry is fully updated before
      // updating pointer lock center. This prevents stale center calculations.
      await parent.target?.canvasModel
          .updateViewStyle(refreshMousePos: updateCursorPos);
      _updateSessionWidthHeight(sessionId);

      // Keep pointer lock center in sync when using relative mouse mode.
      // Note: updatePointerLockCenter is async-safe (handles errors internally),
      // so we fire-and-forget here.
      final inputModel = parent.target?.inputModel;
      if (inputModel != null && inputModel.relativeMouseMode.value) {
        inputModel.updatePointerLockCenter();
      }
    }
  }

  handleSwitchDisplay(
      Map<String, dynamic> evt, SessionID sessionId, String peerId) {
    final display = int.parse(evt['display']);

    if (_pi.currentDisplay != kAllDisplayValue) {
      if (bind.peerGetSessionsCount(
              id: peerId, connType: parent.target!.connType.index) >
          1) {
        if (display != _pi.currentDisplay) {
          return;
        }
      }
      if (!_pi.isSupportMultiUiSession) {
        _pi.currentDisplay = display;
      }
      // If `isSupportMultiUiSession` is true, the switch display message should not be used to update current display.
      // It is only used to update the display info.
    }

    var newDisplay = Display();
    newDisplay.x = double.tryParse(evt['x']) ?? newDisplay.x;
    newDisplay.y = double.tryParse(evt['y']) ?? newDisplay.y;
    newDisplay.width = int.tryParse(evt['width']) ?? newDisplay.width;
    newDisplay.height = int.tryParse(evt['height']) ?? newDisplay.height;
    newDisplay.cursorEmbedded = int.tryParse(evt['cursor_embedded']) == 1;
    newDisplay.originalWidth = int.tryParse(
            evt['original_width'] ?? kInvalidResolutionValue.toString()) ??
        kInvalidResolutionValue;
    newDisplay.originalHeight = int.tryParse(
            evt['original_height'] ?? kInvalidResolutionValue.toString()) ??
        kInvalidResolutionValue;
    newDisplay._scale = _pi.scaleOfDisplay(display);
    _pi.displays[display] = newDisplay;

    if (!_pi.isSupportMultiUiSession || _pi.currentDisplay == display) {
      updateCurDisplay(sessionId);
    }

    if (!_pi.isSupportMultiUiSession) {
      parent.target?.currentDisplay.value = display;
    }

    if (!_pi.isSupportMultiUiSession || _pi.currentDisplay == display) {
      handleResolutions(peerId, evt['resolutions']);
    }
    notifyListeners();
  }

  void cancelPendingMonitorRestore() {
    _pendingRestoreTimer?.cancel();
    _pendingRestoreTimer = null;
    pendingMonitorRestore = null;
  }

  void cancelPendingRestoreTimer() {
    _pendingRestoreTimer?.cancel();
    _pendingRestoreTimer = null;
  }

  _updateSessionWidthHeight(SessionID sessionId) {
    if (_rect == null) return;
    if (_rect!.width <= 0 || _rect!.height <= 0) {
      debugPrintStack(
          label: 'invalid display size (${_rect!.width},${_rect!.height})');
    } else {
      final displays = _pi.getCurDisplays();
      if (displays.length == 1) {
        bind.sessionSetSize(
          sessionId: sessionId,
          display:
              pi.currentDisplay == kAllDisplayValue ? 0 : pi.currentDisplay,
          width: displays[0].width,
          height: displays[0].height,
        );
      } else {
        for (int i = 0; i < displays.length; ++i) {
          bind.sessionSetSize(
            sessionId: sessionId,
            display: i,
            width: displays[i].width,
            height: displays[i].height,
          );
        }
      }
    }
  }

  /// Handle the peer info event based on [evt]. Upstream's tab-to-window cache
  /// ([isCache] true) is gone, so it is always false here; the parameter stays to keep the
  /// body comparable with upstream.
  handlePeerInfo(Map<String, dynamic> evt, String peerId, bool isCache) async {
    // Recent peer is updated by handle_peer_info(ui_session_interface.rs) --> handle_peer_info(client.rs) --> save_config(client.rs)
    bind.mainLoadRecentPeers();

    parent.target?.connection.onPeerInfo();
    _pi.version = evt['version'];
    // Note: Relative mouse mode is NOT auto-enabled on connect.
    // Users must manually enable it via toolbar or keyboard shortcut (Ctrl+Alt+Shift+M).
    //
    // For desktop/webDesktop, keyboard mode initialization is handled later by
    // checkDesktopKeyboardMode() which may change the mode if not supported,
    // followed by updateKeyboardMode() to sync InputModel.keyboardMode.
    // For mobile, updateKeyboardMode() is currently a no-op (only executes on desktop/web),
    // but we call it here for consistency and future-proofing.
    if (isMobile) {
      parent.target?.inputModel.updateKeyboardMode();
    }
    _pi.isSupportMultiUiSession =
        bind.isSupportMultiUiSession(version: _pi.version);
    _pi.username = evt['username'];
    _pi.hostname = evt['hostname'];
    _pi.platform = evt['platform'];
    _pi.sasEnabled = evt['sas_enabled'] == 'true';
    final currentDisplay = int.parse(evt['current_display']);
    if (_pi.primaryDisplay == kInvalidDisplayIndex) {
      _pi.primaryDisplay = currentDisplay;
    }

    if (bind.peerGetSessionsCount(
            id: peerId, connType: parent.target!.connType.index) <=
        1) {
      _pi.currentDisplay = currentDisplay;
    }

    parent.target?.currentDisplay.value = _pi.currentDisplay;

    final connType = parent.target?.connType;
    if (isPeerAndroid) {
      _touchMode = true;
    } else {
      // `kOptionTouchMode` is originally peer option, but it is moved to local option later.
      // We check local option first, if not set, then check peer option.
      // Because if local option is not empty:
      // 1. User has set the touch mode explicitly.
      // 2. The advanced option (custom client) is set.
      //    Then we choose to use the local option.
      final optLocal = bind.mainGetLocalOption(key: kOptionTouchMode);
      if (optLocal != '') {
        _touchMode = optLocal == 'Y';
      } else {
        final optSession = await bind.sessionGetOption(
            sessionId: sessionId, arg: kOptionTouchMode);
        _touchMode = optSession != '';
      }
    }
    if (connType == ConnType.fileTransfer) {
      parent.target?.fileModel.onReady();
    } else if (connType == ConnType.defaultConn ||
        connType == ConnType.viewCamera) {
      List<Display> newDisplays = [];
      List<dynamic> displays = json.decode(evt['displays']);
      for (int i = 0; i < displays.length; ++i) {
        newDisplays.add(evtToDisplay(displays[i]));
      }
      _pi.displays.value = newDisplays;
      _pi.displaysCount.value = _pi.displays.length;
      if (_pi.currentDisplay < _pi.displays.length) {
        // now replaced to _updateCurDisplay
        updateCurDisplay(sessionId);
      }
      // After reconnecting, restore the last selected monitor once the canvas is ready.
      // Switching earlier can offset the view if the monitor sizes differ.
      // New monitor windows keep their selection in currentDisplay.
      final last = lastUserDisplay ?? _pi.currentDisplay;
      pendingMonitorRestore = (!isCache &&
              last != currentDisplay &&
              bind.sessionGetUseAllMyDisplaysForTheRemoteSession(
                      sessionId: sessionId) !=
                  'Y' &&
              ((last == kAllDisplayValue && _pi.displays.isNotEmpty) ||
                  (last >= 0 && last < _pi.displays.length)))
          ? last
          : null;
      // Fallback if the first image event never reaches this tab (multi-UI).
      _pendingRestoreTimer?.cancel();
      if (pendingMonitorRestore != null) {
        _pendingRestoreTimer = Timer(const Duration(milliseconds: 1500),
            () => parent.target?.applyPendingMonitorRestore());
      }
      if (displays.isNotEmpty) {
        parent.target?.connection.onDisplays();
        waitForFirstImage.value = true;
        isRefreshing = false;
      }
      Map<String, dynamic> features = json.decode(evt['features']);
      _pi.features.privacyMode = features['privacy_mode'] == true;
      if (!isCache) {
        handleResolutions(peerId, evt["resolutions"]);
      }
      parent.target?.elevationModel.onPeerInfo(_pi);
    }
    if (connType == ConnType.defaultConn) {
      setViewOnly(
          peerId,
          bind.sessionGetToggleOptionSync(
              sessionId: sessionId, arg: kOptionToggleViewOnly));
      setShowMyCursor(bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: kOptionToggleShowMyCursor));
    }
    if (connType == ConnType.defaultConn || connType == ConnType.viewCamera) {
      final platformAdditions = evt['platform_additions'];
      if (platformAdditions != null && platformAdditions != '') {
        try {
          _pi.platformAdditions = json.decode(platformAdditions);
        } catch (e) {
          debugPrint('Failed to decode platformAdditions $e');
        }
      }
    }

    _pi.isSet.value = true;

    if (isDesktop || isWebDesktop) {
      // checkDesktopKeyboardMode may change the keyboard mode if the current
      // mode is not supported. Re-sync InputModel.keyboardMode afterwards.
      // Note: updateKeyboardMode() is a no-op on mobile (early-returns).
      await checkDesktopKeyboardMode();
      await parent.target?.inputModel.updateKeyboardMode();
    }

    notifyListeners();
  }

  checkDesktopKeyboardMode() async {
    if (isInputSourceFlutter) {
      // Local side, flutter keyboard input source
      // Currently only map mode is supported, legacy mode is used for compatibility.
      for (final mode in [kKeyMapMode, kKeyLegacyMode]) {
        if (bind.sessionIsKeyboardModeSupported(
            sessionId: sessionId, mode: mode)) {
          await bind.sessionSetKeyboardMode(sessionId: sessionId, value: mode);
          break;
        }
      }
    } else {
      final curMode = await bind.sessionGetKeyboardMode(sessionId: sessionId);
      if (curMode != null) {
        if (bind.sessionIsKeyboardModeSupported(
            sessionId: sessionId, mode: curMode)) {
          return;
        }
      }

      // If current keyboard mode is not supported, change to another one.
      for (final mode in [kKeyMapMode, kKeyTranslateMode, kKeyLegacyMode]) {
        if (bind.sessionIsKeyboardModeSupported(
            sessionId: sessionId, mode: mode)) {
          bind.sessionSetKeyboardMode(sessionId: sessionId, value: mode);
          break;
        }
      }
    }
  }

  handleResolutions(String id, dynamic resolutions) {
    try {
      final resolutionsObj = json.decode(resolutions as String);
      late List<dynamic> dynamicArray;
      if (resolutionsObj is Map) {
        // The web version
        dynamicArray = (resolutionsObj as Map<String, dynamic>)['resolutions']
            as List<dynamic>;
      } else {
        // The rust version
        dynamicArray = resolutionsObj as List<dynamic>;
      }
      List<Resolution> arr = List.empty(growable: true);
      for (int i = 0; i < dynamicArray.length; i++) {
        var width = dynamicArray[i]["width"];
        var height = dynamicArray[i]["height"];
        if (width is int && width > 0 && height is int && height > 0) {
          arr.add(Resolution(width, height));
        }
      }
      arr.sort((a, b) {
        if (b.width != a.width) {
          return b.width - a.width;
        } else {
          return b.height - a.height;
        }
      });
      _pi.resolutions = arr;
    } catch (e) {
      debugPrint("Failed to parse resolutions:$e");
    }
  }

  Display evtToDisplay(Map<String, dynamic> evt) {
    var d = Display();
    d.x = evt['x']?.toDouble() ?? d.x;
    d.y = evt['y']?.toDouble() ?? d.y;
    d.width = evt['width'] ?? d.width;
    d.height = evt['height'] ?? d.height;
    d.cursorEmbedded = evt['cursor_embedded'] == 1;
    d.originalWidth = evt['original_width'] ?? kInvalidResolutionValue;
    d.originalHeight = evt['original_height'] ?? kInvalidResolutionValue;
    d._scale = 1.0;
    final scaledWidth = evt['scaled_width'];
    if (scaledWidth != null) {
      final sw = int.tryParse(scaledWidth.toString());
      if (sw != null && sw > 0 && d.width > 0) {
        d._scale = max(d.width.toDouble() / sw, 1.0);
      } else {
        debugPrint(
            "Invalid scaled_width ($scaledWidth) or width (${d.width}), using default scale 1.0");
      }
    }
    return d;
  }

  updateLastCursorId(Map<String, dynamic> evt) {
    // int.parse(evt['id']) may cause FormatException
    // Unhandled Exception: FormatException: Positive input exceeds the limit of integer 18446744071749110741
    parent.target?.cursorModel.id = evt['id'];
  }

  handleCursorId(Map<String, dynamic> evt) {
    parent.target?.cursorModel.updateCursorId(evt);
  }

  /// A shape arriving is the shape in use, as a cursor_id is.
  handleCursorData(String id, int hotx, int hoty, int width, int height,
      Uint8List colors) async {
    parent.target?.cursorModel.id = id;
    await parent.target?.cursorModel
        .updateCursorData(id, hotx, hoty, width, height, colors);
  }

  /// Handle the peer info synchronization event based on [evt].
  handleSyncPeerInfo(
      Map<String, dynamic> evt, SessionID sessionId, String peerId) async {
    if (evt['displays'] != null) {
      List<dynamic> displays = json.decode(evt['displays']);
      List<Display> newDisplays = [];
      for (int i = 0; i < displays.length; ++i) {
        newDisplays.add(evtToDisplay(displays[i]));
      }
      _pi.displays.value = newDisplays;
      _pi.displaysCount.value = _pi.displays.length;

      if (_pi.currentDisplay == kAllDisplayValue) {
        updateCurDisplay(sessionId);
        // to-do: What if the displays are changed?
      } else {
        if (_pi.currentDisplay >= 0 &&
            _pi.currentDisplay < _pi.displays.length) {
          updateCurDisplay(sessionId);
        } else {
          if (_pi.displays.isNotEmpty) {
            // Notify to switch display
            parent.target!.notices
                .add(SessionNotice('display_is_plugged_out_msg'));
            final isPeerPrimaryDisplayValid =
                pi.primaryDisplay == kInvalidDisplayIndex ||
                    pi.primaryDisplay >= pi.displays.length;
            final newDisplay =
                isPeerPrimaryDisplayValid ? 0 : pi.primaryDisplay;
            bind.sessionSwitchDisplay(
              isDesktop: isDesktop,
              sessionId: sessionId,
              value: Int32List.fromList([newDisplay]),
            );

            if (_pi.isSupportMultiUiSession) {
              // If the peer supports multi-ui-session, no switch display message will be send back.
              // We need to update the display manually.
              switchToNewDisplay(newDisplay, sessionId, peerId);
            }
          } else {
            parent.target!.notices.add(SessionNotice('No Displays'));
          }
        }
      }
    }
    parent.target!.canvasModel
        .tryUpdateScrollStyle(Duration(milliseconds: 300), null);
    notifyListeners();
  }

  handlePlatformAdditions(
      Map<String, dynamic> evt, SessionID sessionId, String peerId) async {
    final updateData = evt['platform_additions'] as String?;
    if (updateData == null) {
      return;
    }

    if (updateData.isEmpty) {
      _pi.platformAdditions.remove(kPlatformAdditionsRustDeskVirtualDisplays);
      _pi.platformAdditions.remove(kPlatformAdditionsAmyuniVirtualDisplays);
    } else {
      try {
        final updateJson = json.decode(updateData) as Map<String, dynamic>;
        for (final key in updateJson.keys) {
          _pi.platformAdditions[key] = updateJson[key];
        }
        if (!updateJson
            .containsKey(kPlatformAdditionsRustDeskVirtualDisplays)) {
          _pi.platformAdditions
              .remove(kPlatformAdditionsRustDeskVirtualDisplays);
        }
        if (!updateJson.containsKey(kPlatformAdditionsAmyuniVirtualDisplays)) {
          _pi.platformAdditions.remove(kPlatformAdditionsAmyuniVirtualDisplays);
        }
      } catch (e) {
        debugPrint('Failed to decode platformAdditions $e');
      }
    }
  }

  handleFollowCurrentDisplay(
      Map<String, dynamic> evt, SessionID sessionId, String peerId) async {
    if (evt['display_idx'] != null) {
      if (pi.currentDisplay == kAllDisplayValue) {
        return;
      }
      _pi.currentDisplay = int.parse(evt['display_idx']);
      parent.target?.currentDisplay.value = _pi.currentDisplay;
      bind.sessionSwitchDisplay(
        isDesktop: isDesktop,
        sessionId: sessionId,
        value: Int32List.fromList([_pi.currentDisplay]),
      );
    }
    notifyListeners();
  }

  // Directly switch to the new display without waiting for the response.
  switchToNewDisplay(int display, SessionID sessionId, String peerId,
      {bool updateCursorPos = false}) {
    // no need to wait for the response
    pi.currentDisplay = display;
    updateCurDisplay(sessionId, updateCursorPos: updateCursorPos);
    parent.target?.currentDisplay.value = display;
  }

  updateBlockInputState(Map<String, dynamic> evt, String peerId) {
    _inputBlocked = evt['input_state'] == 'on';
    notifyListeners();
    parent.target?.blockInput.value = evt['input_state'] == 'on';
  }

  updatePrivacyMode(
      Map<String, dynamic> evt, SessionID sessionId, String peerId) async {
    notifyListeners();
    final ffi = parent.target;
    if (ffi == null) return;
    final isOn = bind.sessionGetToggleOptionSync(
        sessionId: sessionId, arg: 'privacy-mode');
    if (isOn) {
      var privacyModeImpl = await bind.sessionGetOption(
          sessionId: sessionId, arg: 'privacy-mode-impl-key');
      // For compatibility, version < 1.2.4, the default value is 'privacy_mode_impl_mag'.
      final initDefaultPrivacyMode = 'privacy_mode_impl_mag';
      ffi.privacyMode.value = privacyModeImpl ?? initDefaultPrivacyMode;
    } else {
      ffi.privacyMode.value = '';
    }
  }

  void setViewOnly(String id, bool value) {
    if (versionCmp(_pi.version, '1.2.0') < 0) return;
    final ffi = parent.target;
    if (ffi != null) {
      if (value) {
        ffi.showRemoteCursor.value = value;
      } else {
        ffi.showRemoteCursor.value = bind.sessionGetToggleOptionSync(
            sessionId: sessionId, arg: 'show-remote-cursor');
      }
    }
    if (_viewOnly != value) {
      _viewOnly = value;
      notifyListeners();
    }
  }

  void setShowMyCursor(bool value) {
    if (_showMyCursor != value) {
      _showMyCursor = value;
      notifyListeners();
    }
  }
}
