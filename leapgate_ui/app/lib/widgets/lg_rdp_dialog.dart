// The dialog that sets how an RDP connection is made (`p8-dlg-rdp*` in
// `A-P8-隧道.html`; 13 §1.3 block D): the port, the user name and the password
// of the remote desktop connection that the RDP card opens. It is built on
// [LgFormDialog]; put it in an `LgDialogScrim` like the other dialogs.
//
// It only draws: the text lives in the controllers of the caller, the words
// come from the caller (localised), and the caller decides when "确定" may be
// pressed and what is wrong with the port.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_device.dart';
import 'lg_feedback.dart';
import 'lg_form_dialog.dart';
import 'lg_panel_inputs.dart';
import 'lg_text_field.dart';

/// The RDP settings of one device: a head with the device's identity-coloured tile carrying the
/// RDP icon, the [title] and under it the device ([deviceName] and its [deviceId]); the three
/// fields with their labels; [runningNote] when the RDP card of this device is running (the new
/// settings take effect after it is stopped and RDP opened again); and the buttons "取消" and
/// "确定".
///
/// [portError] turns the port field red and shows the text under it. The port field asks for the
/// keyboard when the dialog opens. Enter in a field runs [onConfirm]; null greys "确定".
class LgRdpSettingsDialog extends StatelessWidget {
  const LgRdpSettingsDialog({
    super.key,
    required this.title,
    required this.deviceName,
    required this.deviceId,
    required this.portLabel,
    required this.portController,
    required this.usernameLabel,
    required this.usernameController,
    required this.passwordLabel,
    required this.passwordController,
    required this.showPasswordLabel,
    required this.hidePasswordLabel,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.portPlaceholder,
    this.portError,
    this.runningNote,
    this.portFocusNode,
    this.passwordMaxLength,
    this.width = 440,
  });

  /// "RDP 设置".
  final String title;

  /// The device name, null when the device has none (only the ID shows then), and the ID
  /// formatted ("234 567 891", which also gives the tile its colour).
  final String? deviceName;
  final String deviceId;
  final String portLabel;
  final TextEditingController portController;

  /// "3389": what the port is when the field is empty.
  final String? portPlaceholder;
  final String? portError;
  final String usernameLabel;
  final TextEditingController usernameController;
  final String passwordLabel;
  final TextEditingController passwordController;

  /// Names of the eye button in its two states.
  final String showPasswordLabel;
  final String hidePasswordLabel;

  /// The longest password Rust can store (upstream `mainMaxEncryptLen`); no limit by default.
  final int? passwordMaxLength;

  /// "停止后重新打开 RDP，新的设置才会生效。", in a banner under the fields.
  final String? runningNote;
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;
  final FocusNode? portFocusNode;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return LgFormDialog(
      title: title,
      width: width,
      tile: LgDeviceAvatar(
        id: deviceId,
        platform: LgPlatform.unknown,
        icon: LgIcons.rdp,
      ),
      subtitle: ExcludeSemantics(
        child: Row(
          children: [
            if (deviceName case final name?) ...[
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textS.copyWith(color: c.text2),
                ),
              ),
              const SizedBox(width: LgSpace.s2),
            ],
            // The groups of the ID stand 6 px apart (`.id3.sm`).
            Text(
              deviceId,
              maxLines: 1,
              style: t.textS.copyWith(
                color: c.text2,
                fontWeight: FontWeight.w600,
                wordSpacing: 2.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        LgDialogAction(label: cancelLabel, onPressed: onCancel),
        LgDialogAction(
          label: confirmLabel,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: onConfirm,
        ),
      ],
      children: [
        LgFormField(
          label: portLabel,
          child: LgTextField(
            controller: portController,
            focusNode: portFocusNode,
            placeholder: portPlaceholder,
            errorText: portError,
            autofocus: true,
            maxLength: 5,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => onConfirm?.call(),
          ),
        ),
        LgFormField(
          label: usernameLabel,
          child: LgTextField(
            controller: usernameController,
            onSubmitted: (_) => onConfirm?.call(),
          ),
        ),
        LgFormField(
          label: passwordLabel,
          child: LgPasswordField(
            controller: passwordController,
            showLabel: showPasswordLabel,
            hideLabel: hidePasswordLabel,
            maxLength: passwordMaxLength,
            onSubmitted: (_) => onConfirm?.call(),
          ),
        ),
        if (runningNote != null)
          Padding(
            padding: const EdgeInsets.only(top: LgSpace.s4),
            child: LgBanner(tone: LgTone.info, slim: true, text: runningNote),
          ),
      ],
    );
  }
}
