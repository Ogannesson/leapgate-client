// 上游：flutter/lib/models/shortcut_model.dart@bd9262397（只删界面调用，不格式化；registerSessionShortcutActions 整段是界面接线，改写到 app 的 pages/session/toolbar/session_shortcuts.dart）
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../common.dart';
import '../common/widgets/keyboard_shortcuts/shortcut_utils.dart';
import '../common/widgets/keyboard_shortcuts/shortcut_actions.dart';
import '../consts.dart';
import '../leapgate/session.dart';
import '../models/platform_model.dart';

typedef ShortcutCallback = FutureOr<void> Function();

/// Per-session shortcut dispatcher. Attached to FFI when a session is created.
///
/// The Rust matcher (src/keyboard/shortcuts.rs) emits `shortcut_triggered`
/// session events containing the matched `action` id. The session event
/// listener in [FfiModel.startEventListener] forwards those to this model
/// via [onTriggered], which runs whatever callback the toolbar / menu
/// builders previously registered for that action id.
class ShortcutModel {
  static WeakReference<ShortcutModel>? _activeWebModel;

  final WeakReference<FFI> parent;
  final Map<String, ShortcutCallback> _callbacks = {};
  final Map<String, ShortcutCallback> _refreshers = {};

  ShortcutModel(this.parent);

  /// Called by toolbar / menu builders to register what to do when the
  /// matched shortcut fires.
  void register(String actionId, ShortcutCallback callback) {
    if (parent.target?.closed != false) return;
    _callbacks[actionId] = callback;
    _activeWebModel = WeakReference(this);
  }

  void unregister(String actionId) {
    _callbacks.remove(actionId);
  }

  void registerRefresher(List<String> actionIds, ShortcutCallback refresh) {
    if (parent.target?.closed != false) return;
    for (final actionId in actionIds) {
      _refreshers[actionId] = refresh;
    }
  }

  void clear() {
    _callbacks.clear();
    _refreshers.clear();
    if (identical(_activeWebModel?.target, this)) {
      _activeWebModel = null;
    }
  }

  static void onWebTriggered(String actionId) {
    final model = _activeWebModel?.target;
    if (model != null) {
      model.onTriggered(actionId);
    } else {
      debugPrint('shortcut_triggered: no active web shortcut model');
    }
  }

  /// Called by the session event listener when a `shortcut_triggered` event
  /// arrives for this session.
  ///
  /// The matcher has already consumed the chord. With no handler the action
  /// is unavailable in this session (e.g. screenshot on a peer without
  /// support), and the chord is a deliberate no-op: a bound chord always
  /// belongs to RustDesk and is never forwarded to the remote.
  void onTriggered(String actionId) {
    if (parent.target?.closed != false) return;
    unawaited(Future.sync(() async {
      final refresh = _refreshers[actionId];
      if (refresh != null) {
        await refresh();
        if (!identical(_refreshers[actionId], refresh)) return;
      }
      if (parent.target?.closed != false) return;
      final cb = _callbacks[actionId];
      if (cb != null) {
        await cb();
      } else {
        debugPrint('shortcut_triggered: no handler for $actionId');
      }
    }).catchError((e, st) {
      debugPrint('shortcut_triggered: handler failed for $actionId: $e\n$st');
    }));
  }

  static String _configRaw = '';
  static ShortcutConfig _config = ShortcutConfig.parse('');
  static ShortcutConfig _activeConfig = _config;

  /// The stored config, parsed once per distinct stored value. The Flutter
  /// matcher reads it on every key press, so a key press costs one config
  /// read and no JSON parsing while the config is unchanged.
  /// Runtime matching requests [active] to exclude platform-hidden bindings
  /// while retaining the stored config for other platforms.
  static ShortcutConfig config({bool active = false}) {
    final raw = bind.mainGetLocalOption(key: kShortcutLocalConfigKey);
    if (raw != _configRaw) {
      _config = ShortcutConfig.parse(raw);
      _activeConfig = _config.forPlatform(currentPlatformCapabilities());
      _configRaw = raw;
    }
    return active ? _activeConfig : _config;
  }

  /// Read the bindings JSON from LocalConfig. Returns a copy the caller may
  /// edit.
  static List<Map<String, dynamic>> readBindings() => [
        for (final binding in config().bindings)
          Map<String, dynamic>.of(binding)
      ];

  static bool isEnabled() => config().enabled;

  static bool isPassThrough() => config().passThrough;

  /// Persistent companion to [isEnabled]: when on, the matchers return early
  /// and every keystroke flows through to the remote (i.e. all bindings are
  /// suspended). Stored in the same JSON blob so a single reload refreshes
  /// both flags on every active matcher.
  static Future<void> setPassThrough(bool v) async {
    final raw = bind.mainGetLocalOption(key: kShortcutLocalConfigKey);
    Map<String, dynamic> json = {};
    if (raw.isNotEmpty) {
      try {
        json = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        json = {};
      }
    }
    json['pass_through'] = v;
    await bind.mainSetLocalOption(
        key: kShortcutLocalConfigKey, value: jsonEncode(json));
    bind.mainReloadKeyboardShortcuts();
  }

  /// Flip the master `enabled` flag and persist. On the first enable we seed
  /// the default bindings so common combos work out of the box; otherwise we
  /// preserve whatever the user already has, an empty list included. Refreshes the matcher cache so
  /// the change takes effect immediately (Rust on native, JS via the bridge
  /// on Web).
  static Future<void> setEnabled(bool v) async {
    final raw = bind.mainGetLocalOption(key: kShortcutLocalConfigKey);
    Map<String, dynamic> json = {};
    if (raw.isNotEmpty) {
      try {
        json = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        json = {};
      }
    }
    json['enabled'] = v;
    if (v && shouldSeedDefaultShortcutBindings(json)) {
      json['bindings'] = filterDefaultBindingsForPlatform(
        jsonDecode(bind.mainGetDefaultKeyboardShortcuts()) as List,
        currentPlatformCapabilities(),
      );
    } else if (json.containsKey('bindings')) {
      json['bindings'] = shortcutBindingMapsFrom(json['bindings']);
    }
    await bind.mainSetLocalOption(
        key: kShortcutLocalConfigKey, value: jsonEncode(json));
    bind.mainReloadKeyboardShortcuts();
  }

  /// Single source of truth for the per-platform "is this shortcut applicable"
  /// decisions. Both [setEnabled]'s default-seeding pass and the configuration
  /// page's reset / list-rendering paths read from here, so the seed list and
  /// the visible action list can never disagree on which platform a given
  /// action belongs to.
  ///
  /// Capability rationale:
  ///   * Fullscreen / Toolbar / Pin: rendered wherever the
  ///     desktop layout applies (native desktop + Web). Native mobile is
  ///     permanently full-screen and doesn't have a desktop-style toolbar.
  ///   * Screenshot / Switch Sides: native desktop only. The Web bridge
  ///     throws UnimplementedError for `sessionTakeScreenshot`; mobile
  ///     toolbars don't surface either action.
  ///   * Tab navigation / Close Tab: only native desktop ships
  ///     `DesktopTabController`; Web's `RemotePage` is invoked without one.
  ///   * Recording: native desktop has the `_RecordMenu` widget +
  ///     `registerSessionShortcutActions` registration; native Android has
  ///     the `toolbarControls` entry; iOS short-circuits inside
  ///     `recordingModel.toggle()`; Web has no implementation.
  ///   * Reset Canvas: only the mobile toolbar builds the menu entry
  ///     (`isDefaultConn && isMobile` in `toolbarControls`).
  ///   * Voice Call: iOS has no audio capture implementation; Web bridge throws
  ///     `UnimplementedError` for both `sessionRequestVoiceCall` and
  ///     `sessionCloseVoiceCall`.
  static ShortcutPlatformCapabilities currentPlatformCapabilities() {
    final desktopLayout = isDesktop || isWeb;
    return ShortcutPlatformCapabilities(
      includeFullscreenShortcut: desktopLayout,
      includeScreenshotShortcut: isDesktop,
      includeRelativeMouseModeShortcut:
          isDesktop && !(isLinux && bind.mainCurrentIsWayland()),
      includeTabShortcuts: isDesktop,
      includeToolbarShortcut: desktopLayout,
      includeCloseTabShortcut: isDesktop,
      includeSwitchSidesShortcut: isDesktop,
      includeRecordingShortcut: !isWeb && !isIOS,
      includeResetCanvasShortcut: isMobile,
      includePinToolbarShortcut: desktopLayout,
      includeViewModeShortcut: true,
      includeVoiceCallShortcut: !isWeb && !isIOS,
      excludedActions: Set.unmodifiable({
        if (!isDesktop) ...[
          kShortcutActionSwitchDisplayAll,
          kShortcutActionToggleEnableFileCopyPaste,
        ],
        if (isMobile) ...[
          kShortcutActionKeyboardModeLegacy,
          kShortcutActionKeyboardModeMap,
          kShortcutActionKeyboardModeTranslate,
          kShortcutActionToggleShowMyCursor,
          kShortcutActionToggleZoomCursor,
        ],
      }),
    );
  }
}

/// One parsed view of the `keyboard-shortcuts` LocalConfig value. Malformed
/// or missing input parses as disabled with no bindings.
class ShortcutConfig {
  final bool enabled;
  final bool passThrough;
  final List<Map<String, dynamic>> bindings;

  const ShortcutConfig._(this.enabled, this.passThrough, this.bindings);

  ShortcutConfig forPlatform(ShortcutPlatformCapabilities capabilities) {
    final visible = allActionEntries(
            filterKeyboardShortcutActionGroupsForPlatform(capabilities))
        .map((entry) => entry.id)
        .toSet();
    final hidden = allActionEntries(kKeyboardShortcutActionGroups)
        .map((entry) => entry.id)
        .where((id) => !visible.contains(id))
        .toSet();
    return ShortcutConfig._(
      enabled,
      passThrough,
      List.unmodifiable(bindings.where((b) => !hidden.contains(b['action']))),
    );
  }

  static ShortcutConfig parse(String raw) {
    if (raw.isEmpty) return const ShortcutConfig._(false, false, []);
    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      return ShortcutConfig._(
        parsed['enabled'] == true,
        parsed['pass_through'] == true,
        List.unmodifiable(shortcutBindingMapsFrom(parsed['bindings'])),
      );
    } catch (_) {
      return const ShortcutConfig._(false, false, []);
    }
  }
}
