// Leapgate application exit (phase 4): the exit mapping in the TCP tunneling window.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

/// The login target of an exit tunnel; same values as `leapgate::exit` in Rust.
const String kLeapgateExitHost = 'leapgate-exit.invalid';
const int kLeapgateExitPort = 65536;

/// Clear of the usual proxy ports (1080, 7890, 10808/10809, 8080) and of Windows' dynamic
/// range from 49152.
const int kLeapgateExitSuggestedPort = 21180;

const String _kExitHelp =
    'Only TCP. Only programs set to use this proxy go through the exit node. Firefox: Settings, Network Settings, Manual proxy configuration, SOCKS Host 127.0.0.1 and the port of this row, SOCKS v5, and tick "Proxy DNS when using SOCKS v5". Chrome and Edge: use a proxy extension such as SwitchyOmega, or start them with the parameter below. Sites you visit see the remote network\'s address; the remote device logs only refused destinations.';

bool isLeapgateExit(String host, int port) =>
    host == kLeapgateExitHost && port == kLeapgateExitPort;

/// For the connection manager, which gets the normalized `host:port` string.
bool isLeapgateExitAddress(String addr) =>
    addr == '$kLeapgateExitHost:$kLeapgateExitPort';

/// The TCP tunneling window does not register its connection state; the exit row shows it.
void leapgateExitAttach(String id) => ConnectionTypeState.init(id);
void leapgateExitDetach(String id) => ConnectionTypeState.delete(id);

/// Beside the ordinary Add button; one exit mapping per window.
class LeapgateAddExitButton extends StatelessWidget {
  const LeapgateAddExitButton(
      {Key? key,
      required this.ffi,
      required this.hasExit,
      required this.onAdded})
      : super(key: key);
  final FFI ffi;
  final bool hasExit;
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: hasExit ? null : () => _showAddDialog(),
      child: Text(translate('Add exit node')),
    ).marginOnly(right: 10);
  }

  void _showAddDialog() {
    final controller =
        TextEditingController(text: kLeapgateExitSuggestedPort.toString());
    ffi.dialogManager.show((setState, close, context) {
      submit() async {
        final localPort = int.tryParse(controller.text);
        if (localPort == null) return;
        await bind.sessionAddPortForward(
            sessionId: ffi.sessionId,
            localPort: localPort,
            remoteHost: kLeapgateExitHost,
            remotePort: kLeapgateExitPort);
        close();
        onAdded();
      }

      return CustomAlertDialog(
        title: Text(translate('Add exit node')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
              InputDecoration(labelText: translate('Local proxy port')),
          // The ordinary add row's pattern without 0: a 0 port mapping is skipped at start.
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(
                r'^([1-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'))
          ],
        ).workaroundFreezeLinuxMint(),
        actions: [
          dialogButton('Cancel', onPressed: close, isOutline: true),
          dialogButton('OK', onPressed: submit),
        ],
        onSubmit: submit,
        onCancel: close,
      );
    });
  }
}

/// The exit mapping's row in place of an ordinary one.
class LeapgateExitRow extends StatelessWidget {
  const LeapgateExitRow(
      {Key? key,
      required this.id,
      required this.ffi,
      required this.localPort,
      required this.index,
      required this.onRemoved})
      : super(key: key);
  final String id;
  final FFI ffi;
  final int localPort;
  final int index;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    final connectionType = ConnectionTypeState.find(id);
    return Container(
      height: 60,
      decoration: BoxDecoration(
          color: index % 2 == 0
              ? MyTheme.currentThemeMode() == ThemeMode.dark
                  ? const Color(0xFF202020)
                  : const Color(0xFFF4F5F6)
              : Theme.of(context).colorScheme.background),
      child: Row(children: [
        Expanded(
            child: Text(localPort.toString(),
                    style: const TextStyle(fontSize: 20))
                .marginOnly(left: 20)),
        const SizedBox(width: 30, child: Icon(Icons.arrow_forward_sharp)),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('Exit node'),
                  style: const TextStyle(fontSize: 20)),
              // F4: as of the last tunnel set up; a later drop does not update it.
              Obx(() => Text(
                    connectionType.isValid()
                        ? getConnectionText(
                            connectionType.secure.value ==
                                ConnectionType.strSecure,
                            connectionType.direct.value ==
                                ConnectionType.strDirect,
                            '')
                        : translate('Connects on first use'),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  )),
            ],
          ).marginOnly(left: 20),
        ),
        Expanded(
          child: Row(children: [
            _copyButton('SOCKS5', 'Copy SOCKS5 address',
                'socks5h://127.0.0.1:$localPort'),
            _copyButton(
                'HTTP', 'Copy HTTP address', 'http://127.0.0.1:$localPort'),
          ]).marginOnly(left: 10),
        ),
        SizedBox(
          width: 100,
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: _showHelp,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () async {
                await bind.sessionRemovePortForward(
                    sessionId: ffi.sessionId, localPort: localPort);
                onRemoved();
              },
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _copyButton(String label, String tooltip, String address) {
    return Tooltip(
      message: translate(tooltip),
      child: TextButton.icon(
        icon: const Icon(Icons.copy, size: 14),
        label: Text(label),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: address));
          showToast(translate('Copied'));
        },
      ),
    );
  }

  void _showHelp() {
    ffi.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(translate('Exit node')),
        content: SelectableText(
            '${translate(_kExitHelp)}\n\n--proxy-server=socks5://127.0.0.1:$localPort'),
        actions: [dialogButton('OK', onPressed: close)],
        onSubmit: close,
        onCancel: close,
      );
    }, clickMaskDismiss: true, backDismiss: true);
  }
}
