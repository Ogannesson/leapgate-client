// The incoming sessions section (02 §1.3.5) and the recording location it shares with "会话期间"
// (02 §1.4.3): what is not an option the page reads through `OptionScope`. Upstream:
// `desktop_setting_page.dart` `autoDisconnect`, `wallpaper`, `shareRdp`, `privacyModeImpl`,
// `record`; `common/widgets/audio_input.dart`.
import 'dart:convert';
import 'dart:io';

import '../../consts.dart';
import '../../models/platform_model.dart';
import '../options.dart';

/// "时长" as typed: the value to store ('' for upstream's 10 minutes), or null when it is not a
/// whole number from 1 to 65535. Upstream also took 0 for 10 (02 §1.3.5).
String? parseAutoDisconnectMinutes(String text) {
  final t = text.trim();
  if (t.isEmpty) return '';
  if (!RegExp(r'^[1-9]\d{0,4}$').hasMatch(t)) return null;
  return int.parse(t) <= 65535 ? t : null;
}

/// The sources of "声音来源" (upstream `AudioInput.getDevicesInfo` for the settings): [loopback]
/// is "系统声音", stored as '' and listed first; [current] is the stored value.
typedef SoundSources = ({bool loopback, List<String> devices, String current});

extension SoundSourcesShown on SoundSources {
  /// No source at all hides the row (02 §1.3.5).
  bool get isEmpty => !loopback && devices.isEmpty;
}

Future<SoundSources> readSoundSources(OptionScope config) async => (
      loopback: bind.mainAudioSupportLoopback(),
      devices: (await bind.mainGetSoundInputs()).toList(),
      current: config.get(kOptionAudioInput),
    );

/// The privacy mode methods this device has (`privacy_mode.rs`
/// `get_supported_privacy_mode_impl`): their keys and Rust's name keys. The choice is shown
/// with two or more (02 §1.3.5).
List<(String key, String name)> privacyModeImpls() => [
      for (final i in jsonDecode(bind.mainSupportedPrivacyModeImpls()) as List)
        ((i as List)[0] as String, i[1] as String),
    ];

/// The method in use: Rust's default when none is stored.
String privacyModeImpl(OptionScope config) {
  final v = config.get(kOptionPrivacyModeImpl);
  return v.isEmpty ? bind.mainDefaultPrivacyModeImpl() : v;
}

/// Whether this system can remove the wallpaper; null until read (the section reads it once a
/// run, search lists the row after that).
bool? wallpaperSupported;

Future<bool> readWallpaperSupport() async =>
    wallpaperSupported ??= await bind.mainSupportRemoveWallpaper();

/// "预览": the wallpaper goes for [seconds].
Future<void> previewWallpaper(int seconds) =>
    bind.mainTestWallpaper(second: seconds);

bool shareRdp() => bind.mainIsShareRdp();

/// Asks for administrator permission itself; true when the value is [on] afterwards (cancelled
/// or failed leaves it as it was, 09 §1.2).
Future<bool> setShareRdp(bool on) async {
  await bind.mainSetShareRdp(enable: on);
  return bind.mainIsShareRdp() == on;
}

/// The recording folder (`ui_interface.rs` `video_save_directory`): [incoming] on the installed
/// version is the service's, which can't be changed; otherwise the one folder both directions
/// use, `video-save-directory` in LocalConfig.
class RecordingFolder {
  const RecordingFolder({required this.path, required this.exists});

  final String path;
  final bool exists;
}

/// On the installed version incoming sessions are recorded by the service into its own folder.
bool serviceRecordsIncoming() => Platform.isWindows && bind.mainIsInstalled();

RecordingFolder readRecordingFolder({required bool service}) {
  final path = bind.mainVideoSaveDirectory(root: service);
  return RecordingFolder(path: path, exists: Directory(path).existsSync());
}

Future<bool> setRecordingFolder(OptionScope local, String path) =>
    local.set(kOptionVideoSaveDirectory, path);

/// Opens [path] in the system's file manager (upstream `launchUrl(Uri.file(…))`).
Future<void> openFolder(String path) async {
  if (Platform.isWindows) await Process.start('explorer.exe', [path]);
}
