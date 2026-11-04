// 上游：flutter/lib/consts.dart@bd9262397（改写：部分复制，只收 core 里的 models 用到的常量，各段照上游原样、按上游顺序；kDragToResizeAreaPadding 见那一行的说明）
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

export 'common/widgets/keyboard_shortcuts/shortcut_constants.dart';

const int kMaxVirtualDisplayCount = 4;
const int kAllVirtualDisplay = -1;

const double kDesktopRemoteTabBarHeight = 28.0;

const kAllDisplayValue = -1;

const kKeyLegacyMode = 'legacy';

const kKeyMapMode = 'map';

const kKeyTranslateMode = 'translate';

const String kPlatformAdditionsIsWayland = "is_wayland";

const String kPlatformAdditionsIsInstalled = "is_installed";

const String kPlatformAdditionsIddImpl = "idd_impl";

const String kPlatformAdditionsRustDeskVirtualDisplays =
    "rustdesk_virtual_displays";

const String kPlatformAdditionsAmyuniVirtualDisplays =
    "amyuni_virtual_displays";
const String kPlatformAdditionsHasFileClipboard = "has_file_clipboard";
const String kPlatformAdditionsSupportedPrivacyModeImpl =
    "supported_privacy_mode_impl";

const String kPrivacyModeImplMag = 'privacy_mode_impl_mag';
const String kPrivacyModeImplExcludeFromCapture =
    'privacy_mode_impl_exclude_from_capture';

const String kPeerPlatformWindows = "Windows";

const String kPeerPlatformLinux = "Linux";

const String kPeerPlatformMacOS = "Mac OS";

const String kPeerPlatformAndroid = "Android";

/// [kAppTypeMain] used by 'Desktop Main Page' , 'Mobile (Client and Server)', "Install Page"
const String kAppTypeMain = "main";

const String kAppTypeDesktopRemote = "remote";

const String kOptionForceAlwaysRelay = "force-always-relay";
const String kOptionAccessMode = "access-mode";
const String kOptionAllowRemoteConfigModification =
    "allow-remote-config-modification";
const String kOptionAllowAutoRecordOutgoing = "allow-auto-record-outgoing";
const String kOptionHideRecordingButton = "hide-recording-button";
const String kOptionVerificationMethod = "verification-method";
const String kOptionApproveMode = "approve-mode";
const String kOptionCollapseToolbar = "collapse_toolbar";
const String kOptionZoomCursor = "zoom-cursor";
const String kOptionEnableFileCopyPaste = "enable-file-copy-paste";
const String kOptionTouchMode = "touch-mode";
const String kOptionCodecPreference = "codec-preference";
const String kOptionRemoteMenubarDragLeft = "remote-menubar-drag-left";
const String kOptionRemoteMenubarDragRight = "remote-menubar-drag-right";
const String kOptionRemoteMenubarEdge = "remote-menubar-edge";
const String kOptionRemoteMenubarFraction = "remote-menubar-frac";
const String kOptionAllowMultiEdgeToolbarDock =
    "allow-multi-edge-toolbar-dock";
const String kOptionRemoteMenubarState = "remoteMenubarState";
const String kOptionPeerSorting = "peer-sorting";
const String kOptionPeerTabIndex = "peer-tab-index";
const String kOptionPeerTabOrder = "peer-tab-order";
const String kOptionPeerTabVisible = "peer-tab-visible";
const String kOptionPeerCardUiType = "peer-card-ui-type";
const String kOptionEnableConfirmClosingTabs = "enable-confirm-closing-tabs";
const String kOptionStopService = "stop-service";
const String kOptionAllowMonitorSwitchMainToolbar = "allow-monitor-switch-main-toolbar";
const String kOptionAllowMonitorSwitchMinToolbar = "allow-monitor-switch-min-toolbar";

const String kOptionToggleViewOnly = "view-only";

const String kOptionToggleShowMyCursor = "show-my-cursor";

const String kOptionShowMobileAction = "showMobileActions";

const String kPointerEventKindTouch = "touch";

const String kPointerEventKindMouse = "mouse";

const String kMouseEventTypeDefault = "";

const String kMouseEventTypePanStart = "pan_start";

const String kMouseEventTypePanUpdate = "pan_update";

const String kMouseEventTypePanEnd = "pan_end";

const String kMouseEventTypeDown = "down";

const String kMouseEventTypeUp = "up";

const String kKeyFlutterKey = "flutter_key";

const String kKeyShowMonitorsToolbar = 'show_monitors_toolbar';
const String kKeyReverseMouseWheel = "reverse_mouse_wheel";

const String kMsgboxTextWaitingForImage = 'Connected, waiting for image...';

const int kMobileDefaultDisplayWidth = 720;

const int kMobileDefaultDisplayHeight = 1280;

const int kDesktopDefaultDisplayWidth = 1080;

const int kDesktopDefaultDisplayHeight = 720;

const double kMinFps = 5;
const double kDefaultFps = 30;
const double kMaxFps = 120;

const double kMinQuality = 10;
const double kDefaultQuality = 50;
const double kMaxQuality = 100;
const double kMaxMoreQuality = 2000;

const int kMinTrackpadSpeed = 10;

const int kDefaultTrackpadSpeed = 100;

const int kMaxTrackpadSpeed = 1000;

/// Minimum server version required for relative mouse mode (MOUSE_TYPE_MOVE_RELATIVE).
/// Servers older than this version will ignore relative mouse events.
///
/// IMPORTANT: This value must be kept in sync with the Rust constant
/// `MIN_VERSION_RELATIVE_MOUSE_MODE` in `src/common.rs`.
const String kMinVersionForRelativeMouseMode = '1.4.5';

/// Maximum delta value for relative mouse movement.
/// Large values could cause issues with i32 overflow on server side,
/// and no reasonable mouse movement should exceed this bound.
///
/// IMPORTANT: This value must be kept in sync with the Rust constant
/// `MAX_RELATIVE_MOUSE_DELTA` in `src/server/input_service.rs`.
const int kMaxRelativeMouseDelta = 10000;

/// Debounce duration (in milliseconds) for relative mouse mode toggle.
/// This prevents double-toggle from race condition between Rust rdev grab loop
/// and Flutter keyboard handling. Value should be small enough to allow
/// intentional quick toggles but large enough to prevent accidental double-triggers.
const int kRelativeMouseModeToggleDebounceMs = 150;

// incomming (should be incoming) is kept, because change it will break the previous setting.
const String kKeyPrinterIncomingJobAction = 'printer-incomming-job-action';

const String kValuePrinterIncomingJobDismiss = 'dismiss';

const String kValuePrinterIncomingJobDefault = '';

const String kValuePrinterIncomingJobSelected = 'selected';

const String kKeyPrinterSelected = 'printer-selected-name';

const String kKeyPrinterAllowAutoPrint = 'allow-printer-auto-print';

// Upstream (:342-346) leaves a resize border only on Linux without the compatible UI mode; the
// new UI is Windows-only for now, where it is zero.
const kDragToResizeAreaPadding = EdgeInsets.zero;

/// [kMinCursorSize] indicates min cursor (w, h)
const int kMinCursorSize = 12;

final kWindowBorderWidth = isWindows ? 0.0 : 1.0;

/// [kMouseControlDistance] indicates the distance that self-side move to get control of mouse.
const kMouseControlDistance = 12;

/// [kMouseControlTimeoutMSec] indicates the timeout (in milliseconds) that self-side can get control of mouse.
const kMouseControlTimeoutMSec = 1000;

/// [kRemoteViewStyleOriginal] Show remote image without scaling.
const kRemoteViewStyleOriginal = 'original';

/// [kRemoteViewStyleAdaptive] Show remote image scaling by ratio factor.
const kRemoteViewStyleAdaptive = 'adaptive';

/// [kRemoteViewStyleCustom] Show remote image at a user-defined scale percent.
const kRemoteViewStyleCustom = 'custom';

/// [kRemoteScrollStyleAuto] Scroll image auto by position.
const kRemoteScrollStyleAuto = 'scrollauto';

/// [kRemoteScrollStyleBar] Scroll image with scroll bar.
const kRemoteScrollStyleBar = 'scrollbar';

/// [kRemoteScrollStyleEdge] Scroll image auto at edges.
const kRemoteScrollStyleEdge = 'scrolledge';

/// [kRemoteImageQualityBest] Best image quality.
const kRemoteImageQualityBest = 'best';

/// [kRemoteImageQualityBalanced] Balanced image quality, mid performance.
const kRemoteImageQualityBalanced = 'balanced';

/// [kRemoteImageQualityLow] Low image quality, better performance.
const kRemoteImageQualityLow = 'low';

/// [kRemoteImageQualityCustom] Custom image quality.
const kRemoteImageQualityCustom = 'custom';

const kIgnoreDpi = true;

// Scale custom related constants
const String kCustomScalePercentKey =
    'custom_scale_percent'; // Flutter option key for storing custom scale percent (integer 5-1000)
const int kScaleCustomMinPercent = 5;
const int kScaleCustomPivotPercent = 100; // 100% should be at 1/3 of track

const int kScaleCustomMaxPercent = 1000;
const double kScaleCustomPivotPos = 1.0 / 3.0; // first 1/3 → up to 100%
const double kScaleCustomDetentEpsilon =
    0.006; // snap range around pivot (~0.6%)
const Duration kDebounceCustomScaleDuration = Duration(milliseconds: 300);

/// Android channel invoke type key
class AndroidChannel {
  static final kStartAction = "start_action";
  static final kGetStartOnBootOpt = "get_start_on_boot_opt";
  static final kSetStartOnBootOpt = "set_start_on_boot_opt";
  static final kSyncAppDirConfigPath = "sync_app_dir";
  static final kPickImportFiles = "pick_import_files";
  static final kImportFile = "import_file";
  static final kExportFile = "export_file";
  static final kPickImportDirectory = "pick_import_directory";
  static final kImportDirectory = "import_directory";
  static final kExportFiles = "export_files";
}

/// flutter/packages/flutter/lib/src/services/keyboard_key.dart -> _keyLabels
/// see [LogicalKeyboardKey.keyLabel]
const Map<int, String> logicalKeyMap = <int, String>{
  0x00000000020: 'VK_SPACE',
  0x00000000022: 'VK_QUOTE',
  0x0000000002c: 'VK_COMMA',
  0x0000000002d: 'VK_MINUS',
  0x0000000002f: 'VK_SLASH',
  0x00000000030: 'VK_0',
  0x00000000031: 'VK_1',
  0x00000000032: 'VK_2',
  0x00000000033: 'VK_3',
  0x00000000034: 'VK_4',
  0x00000000035: 'VK_5',
  0x00000000036: 'VK_6',
  0x00000000037: 'VK_7',
  0x00000000038: 'VK_8',
  0x00000000039: 'VK_9',
  0x0000000003b: 'VK_SEMICOLON',
  0x0000000003d: 'VK_PLUS', // it is =
  0x0000000005b: 'VK_LBRACKET',
  0x0000000005c: 'VK_BACKSLASH',
  0x0000000005d: 'VK_RBRACKET',
  0x00000000061: 'VK_A',
  0x00000000062: 'VK_B',
  0x00000000063: 'VK_C',
  0x00000000064: 'VK_D',
  0x00000000065: 'VK_E',
  0x00000000066: 'VK_F',
  0x00000000067: 'VK_G',
  0x00000000068: 'VK_H',
  0x00000000069: 'VK_I',
  0x0000000006a: 'VK_J',
  0x0000000006b: 'VK_K',
  0x0000000006c: 'VK_L',
  0x0000000006d: 'VK_M',
  0x0000000006e: 'VK_N',
  0x0000000006f: 'VK_O',
  0x00000000070: 'VK_P',
  0x00000000071: 'VK_Q',
  0x00000000072: 'VK_R',
  0x00000000073: 'VK_S',
  0x00000000074: 'VK_T',
  0x00000000075: 'VK_U',
  0x00000000076: 'VK_V',
  0x00000000077: 'VK_W',
  0x00000000078: 'VK_X',
  0x00000000079: 'VK_Y',
  0x0000000007a: 'VK_Z',
  0x00100000008: 'VK_BACK',
  0x00100000009: 'VK_TAB',
  0x0010000000d: 'VK_ENTER',
  0x0010000001b: 'VK_ESCAPE',
  0x0010000007f: 'VK_DELETE',
  0x00100000104: 'VK_CAPITAL',
  0x00100000301: 'VK_DOWN',
  0x00100000302: 'VK_LEFT',
  0x00100000303: 'VK_RIGHT',
  0x00100000304: 'VK_UP',
  0x00100000305: 'VK_END',
  0x00100000306: 'VK_HOME',
  0x00100000307: 'VK_NEXT',
  0x00100000308: 'VK_PRIOR',
  0x00100000401: 'VK_CLEAR',
  0x00100000407: 'VK_INSERT',
  0x00100000504: 'VK_CANCEL',
  0x00100000506: 'VK_EXECUTE',
  0x00100000508: 'VK_HELP',
  0x00100000509: 'VK_PAUSE',
  0x0010000050c: 'VK_SELECT',
  0x00100000608: 'VK_PRINT',
  0x00100000705: 'VK_CONVERT',
  0x00100000706: 'VK_FINAL',
  0x00100000711: 'VK_HANGUL',
  0x00100000712: 'VK_HANJA',
  0x00100000713: 'VK_JUNJA',
  0x00100000718: 'VK_KANA',
  0x00100000719: 'VK_KANJI',
  0x00100000801: 'VK_F1',
  0x00100000802: 'VK_F2',
  0x00100000803: 'VK_F3',
  0x00100000804: 'VK_F4',
  0x00100000805: 'VK_F5',
  0x00100000806: 'VK_F6',
  0x00100000807: 'VK_F7',
  0x00100000808: 'VK_F8',
  0x00100000809: 'VK_F9',
  0x0010000080a: 'VK_F10',
  0x0010000080b: 'VK_F11',
  0x0010000080c: 'VK_F12',
  0x00100000d2b: 'Apps',
  0x00200000002: 'VK_SLEEP',
  0x00200000100: 'VK_CONTROL',
  0x00200000101: 'RControl',
  0x00200000102: 'VK_SHIFT',
  0x00200000103: 'RShift',
  0x00200000104: 'VK_MENU',
  0x00200000105: 'RAlt',
  0x002000001f0: 'VK_CONTROL',
  0x002000001f2: 'VK_SHIFT',
  0x002000001f4: 'VK_MENU',
  0x002000001f6: 'Meta',
  0x0020000022a: 'VK_MULTIPLY',
  0x0020000022b: 'VK_ADD',
  0x0020000022d: 'VK_SUBTRACT',
  0x0020000022e: 'VK_DECIMAL',
  0x0020000022f: 'VK_DIVIDE',
  0x00200000230: 'VK_NUMPAD0',
  0x00200000231: 'VK_NUMPAD1',
  0x00200000232: 'VK_NUMPAD2',
  0x00200000233: 'VK_NUMPAD3',
  0x00200000234: 'VK_NUMPAD4',
  0x00200000235: 'VK_NUMPAD5',
  0x00200000236: 'VK_NUMPAD6',
  0x00200000237: 'VK_NUMPAD7',
  0x00200000238: 'VK_NUMPAD8',
  0x00200000239: 'VK_NUMPAD9',
};

/// flutter/packages/flutter/lib/src/services/keyboard_key.dart -> _debugName
/// see [PhysicalKeyboardKey.debugName] -> _debugName
const Map<int, String> physicalKeyMap = <int, String>{
  0x00010082: 'VK_SLEEP',
  0x00070004: 'VK_A',
  0x00070005: 'VK_B',
  0x00070006: 'VK_C',
  0x00070007: 'VK_D',
  0x00070008: 'VK_E',
  0x00070009: 'VK_F',
  0x0007000a: 'VK_G',
  0x0007000b: 'VK_H',
  0x0007000c: 'VK_I',
  0x0007000d: 'VK_J',
  0x0007000e: 'VK_K',
  0x0007000f: 'VK_L',
  0x00070010: 'VK_M',
  0x00070011: 'VK_N',
  0x00070012: 'VK_O',
  0x00070013: 'VK_P',
  0x00070014: 'VK_Q',
  0x00070015: 'VK_R',
  0x00070016: 'VK_S',
  0x00070017: 'VK_T',
  0x00070018: 'VK_U',
  0x00070019: 'VK_V',
  0x0007001a: 'VK_W',
  0x0007001b: 'VK_X',
  0x0007001c: 'VK_Y',
  0x0007001d: 'VK_Z',
  0x0007001e: 'VK_1',
  0x0007001f: 'VK_2',
  0x00070020: 'VK_3',
  0x00070021: 'VK_4',
  0x00070022: 'VK_5',
  0x00070023: 'VK_6',
  0x00070024: 'VK_7',
  0x00070025: 'VK_8',
  0x00070026: 'VK_9',
  0x00070027: 'VK_0',
  0x00070028: 'VK_ENTER',
  0x00070029: 'VK_ESCAPE',
  0x0007002a: 'VK_BACK',
  0x0007002b: 'VK_TAB',
  0x0007002c: 'VK_SPACE',
  0x0007002d: 'VK_MINUS',
  0x0007002e: 'VK_PLUS', // it is =
  0x0007002f: 'VK_LBRACKET',
  0x00070030: 'VK_RBRACKET',
  0x00070033: 'VK_SEMICOLON',
  0x00070034: 'VK_QUOTE',
  0x00070036: 'VK_COMMA',
  0x00070038: 'VK_SLASH',
  0x00070039: 'VK_CAPITAL',
  0x0007003a: 'VK_F1',
  0x0007003b: 'VK_F2',
  0x0007003c: 'VK_F3',
  0x0007003d: 'VK_F4',
  0x0007003e: 'VK_F5',
  0x0007003f: 'VK_F6',
  0x00070040: 'VK_F7',
  0x00070041: 'VK_F8',
  0x00070042: 'VK_F9',
  0x00070043: 'VK_F10',
  0x00070044: 'VK_F11',
  0x00070045: 'VK_F12',
  0x00070049: 'VK_INSERT',
  0x0007004a: 'VK_HOME',
  0x0007004b: 'VK_PRIOR', // Page Up
  0x0007004c: 'VK_DELETE',
  0x0007004d: 'VK_END',
  0x0007004e: 'VK_NEXT', // Page Down
  0x0007004f: 'VK_RIGHT',
  0x00070050: 'VK_LEFT',
  0x00070051: 'VK_DOWN',
  0x00070052: 'VK_UP',
  0x00070053: 'Num Lock', // TODO rust not impl
  0x00070054: 'VK_DIVIDE', // numpad
  0x00070055: 'VK_MULTIPLY',
  0x00070056: 'VK_SUBTRACT',
  0x00070057: 'VK_ADD',
  0x00070058: 'VK_ENTER', // num enter
  0x00070059: 'VK_NUMPAD1',
  0x0007005a: 'VK_NUMPAD2',
  0x0007005b: 'VK_NUMPAD3',
  0x0007005c: 'VK_NUMPAD4',
  0x0007005d: 'VK_NUMPAD5',
  0x0007005e: 'VK_NUMPAD6',
  0x0007005f: 'VK_NUMPAD7',
  0x00070060: 'VK_NUMPAD8',
  0x00070061: 'VK_NUMPAD9',
  0x00070062: 'VK_NUMPAD0',
  0x00070063: 'VK_DECIMAL',
  0x00070075: 'VK_HELP',
  0x00070077: 'VK_SELECT',
  0x00070088: 'VK_KANA',
  0x0007008a: 'VK_CONVERT',
  0x000700e0: 'VK_CONTROL',
  0x000700e1: 'VK_SHIFT',
  0x000700e2: 'VK_MENU',
  0x000700e3: 'Meta',
  0x000700e4: 'RControl',
  0x000700e5: 'RShift',
  0x000700e6: 'RAlt',
  0x000700e7: 'RWin',
  0x000c00b1: 'VK_PAUSE',
  0x000c00cd: 'VK_PAUSE',
  0x000c019e: 'LOCK_SCREEN',
  0x000c0208: 'VK_PRINT',
};

// The connection manager (M3), in upstream's order.

/// [kAppTypeConnectionManager] only for 'Desktop CM Page'
const String kAppTypeConnectionManager = "cm";

const String kOptionEnablePermChangeInAcceptWindow =
    "enable-perm-change-in-accept-window";
const String kOptionHideElevateButtonInAcceptWindow =
    "hide-elevate-button-in-accept-window";
const String kOptionAllowRemoteCmModification = "allow-remote-cm-modification";

// The address book (M4): upstream's `consts.dart` keys, then those of `models/ab_model.dart`,
// under their upstream names.

const String kOptionHideAbTagsPanel = "hideAbTagsPanel";
const String kOptionCurrentAbName = "current-ab-name";

const String syncAbOption = 'sync-ab-with-recent-sessions';
const String sortAbTagsOption = 'sync-ab-tags';
const String filterAbTagOption = 'filter-ab-by-intersection';

/// LocalConfig: the exit nodes' local proxy ports as JSON `{device ID: port}` (M5-6), Leapgate's
/// own; the old UI kept its exit port in the device's port forwards.
const String kOptionLeapgateExitPorts = 'leapgate-exit-ports';

// M6a: keys both settings lanes read (`LEAPGATE.md` §10.13). Each lane appends the rest below,
// coder A under "M6a access", coder B under "M6a network".

/// Config: the exit node switch; Rust only takes "Y" (第四期 A5), the page writes Y / N.
const String kOptionLeapgateAllowExit = 'leapgate-allow-exit';
const String kOptionEnableTunnel = 'enable-tunnel';

/// LocalConfig, shared with the old UI: `light`, `dark`, anything else follows the system
/// (upstream `common.dart:579-630`).
const String kCommConfKeyTheme = 'theme';

/// LocalConfig, shared with the old UI: Rust's language code (`zh-cn`, `en`), empty follows the
/// system.
const String kCommConfKeyLang = 'lang';

// M6a access (upstream `flutter/lib/consts.dart`).

const String kOptionTemporaryPasswordLength = 'temporary-password-length';
const String kOptionAllowNumericOneTimePassword =
    'allow-numeric-one-time-password';
const String kOptionEnableKeyboard = 'enable-keyboard';
const String kOptionEnableRemotePrinter = 'enable-remote-printer';
const String kOptionEnableClipboard = 'enable-clipboard';
const String kOptionEnableFileTransfer = 'enable-file-transfer';
const String kOptionEnableAudio = 'enable-audio';
const String kOptionEnableCamera = 'enable-camera';
const String kOptionEnableTerminal = 'enable-terminal';
const String kOptionEnableRemoteRestart = 'enable-remote-restart';
const String kOptionEnableRecordSession = 'enable-record-session';
const String kOptionEnableBlockInput = 'enable-block-input';
const String kOptionEnablePrivacyMode = 'enable-privacy-mode';

// M6a network: upstream's names and values (`flutter/lib/consts.dart:179-199`).

/// LocalConfig, read by the controlling side.
const String kOptionEnableTcpPunch = "enable-tcp-punch";
const String kOptionEnableUdpPunch = "enable-udp-punch";
const String kOptionEnableIpv6Punch = "enable-ipv6-punch";
const String kOptionRelayFallbackDelay = "relay-fallback-delay";

/// Config, read by both sides.
const String kOptionAllowWebSocket = "allow-websocket";
const String kOptionAllowInsecureTLSFallback = "allow-insecure-tls-fallback";
const String kOptionDisableUdp = "disable-udp";

// M6b incoming (coder C, `LEAPGATE.md` §10.14): upstream's names and values.

// M6b outgoing (coder D, `LEAPGATE.md` §10.14): upstream's names and values.
