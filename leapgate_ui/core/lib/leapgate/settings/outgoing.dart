// What the outgoing sections and "其他" read from Rust beside the options (02 §1.4.2, §1.4.5,
// §1.5.4): the decoders this device has, the texture rendering as Rust decides it, the hardware
// codec. Upstream reads these in `desktop_setting_page.dart` (`codec`, `other`, `hwcodec`).
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../consts.dart';
import '../../models/platform_model.dart';
import '../options.dart';

/// UserDefaultConfig's on / off options: Rust stores 'Y' for on; upstream writes 'N' for off on
/// a custom client (`setting_widgets.dart` `otherRow`, `defaultOptionNo`), which Leapgate is.
bool defaultOn(OptionScope defaults, String key) => defaults.get(key) == 'Y';

Future<bool> setDefaultOn(OptionScope defaults, String key, bool on) =>
    defaults.set(key, on ? 'Y' : 'N');

/// The codecs a new device may start with: VP8, VP9 and AV1 always (software decoding), H264
/// and H265 when this device can decode them in hardware (`mainSupportedHwdecodings`).
List<String> defaultCodecChoices() {
  final codecs = ['auto', 'vp8', 'vp9', 'av1'];
  try {
    final hw = jsonDecode(bind.mainSupportedHwdecodings()) as Map;
    if (hw['h264'] == true) codecs.add('h264');
    if (hw['h265'] == true) codecs.add('h265');
  } catch (e) {
    debugPrint('failed to parse supported hwdecodings, err=$e');
  }
  return codecs;
}

/// "使用纹理渲染" as Rust takes it: an unset key is on from Windows 10 (`src/ui_interface.rs`
/// `get_use_texture_render`).
bool textureRenderOn() => bind.mainGetUseTextureRender();

/// Rust tells the open sessions itself (`main_set_local_option`, the `use_texture_render` event
/// and the decoders for D3D), so the sessions follow at once.
Future<bool> setTextureRender(OptionScope local, bool on) =>
    local.set(kOptionTextureRender, on ? 'Y' : 'N');

/// "硬件编解码" is shown when this build has a hardware codec or this device a usable GPU.
bool hasHardwareCodec() => bind.mainHasHwcodec() || bind.mainHasVram();

/// Turning it on has Rust find out what the hardware can do, as upstream.
Future<bool> setHardwareCodec(OptionScope config, bool on) async {
  final saved = await config.setBool(kOptionEnableHwcodec, on);
  if (saved && on) await bind.mainCheckHwcodec();
  return saved;
}
