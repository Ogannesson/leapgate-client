// Leapgate application exit (phase 4), controlled side: the exit node card on the security
// settings page. A part of desktop_setting_page.dart, so it uses that page's private widgets.
part of '../desktop/pages/desktop_setting_page.dart';

// Same keys as `leapgate::exit` in Rust; both live in Config, which the service process reads.
const _kLeapgateOptionAllowExit = 'leapgate-allow-exit';
const _kLeapgateOptionAllowNets = 'leapgate-exit-allow-nets';

Widget buildLeapgateExitSettings(BuildContext context,
    {required bool enabled}) {
  note(String text) => Text(
        translate(text),
        style:
            TextStyle(fontSize: 12, color: disabledTextColor(context, enabled)),
      ).marginOnly(left: _kContentHMargin);
  return _Card(title: 'Exit node settings', children: [
    // Only "Y" is on: the default getter would take an unset key for on.
    _OptionCheckBox(context, 'Allow this device to act as an exit node',
        _kLeapgateOptionAllowExit,
        enabled: enabled,
        optGetter: () =>
            bind.mainGetOptionSync(key: _kLeapgateOptionAllowExit) == 'Y'),
    _Button('Allowed destination networks', _leapgateChangeAllowNets,
        enabled: enabled),
    note(
        "Exit traffic leaves through this device's physical network adapter, bypassing its proxy and VPN."),
    note(
        'For an unattended exit, set a permanent password and choose "Accept sessions via password".'),
    note(
        'To keep exit users off the local network, also turn off "Enable TCP tunneling".'),
    note(
        'This switch is independent of the access mode, including Screen Share.'),
    note(
        'Only refused destination IP addresses are logged, at most one entry per minute; successful destinations and domain names are not logged.'),
  ]);
}

/// The syntax of Rust's `parse_allow_nets`, which has the last word: an IP address with an
/// optional prefix length, no names, ports or zone IDs.
bool _leapgateIsNet(String item) {
  final slash = item.indexOf('/');
  final addr = slash < 0 ? item : item.substring(0, slash);
  final prefix = slash < 0 ? null : item.substring(slash + 1);
  final int max;
  if (addr.contains(':')) {
    try {
      Uri.parseIPv6Address(addr);
    } on FormatException {
      return false;
    }
    max = 128;
  } else {
    final ipv4 = RegExp(
        r"^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$");
    if (!ipv4.hasMatch(addr)) return false;
    max = 32;
  }
  if (prefix == null) return true;
  return RegExp(r'^\d{1,3}$').hasMatch(prefix) && int.parse(prefix) <= max;
}

void _leapgateChangeAllowNets() async {
  final current = await bind.mainGetOption(key: _kLeapgateOptionAllowNets);
  final controller = TextEditingController(text: current.split(',').join('\n'));
  var msg = '';
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('Allowed destination networks')),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(translate(
              'Enter IP addresses or CIDR networks, separated by commas, spaces or newlines. Hard-blocked addresses cannot be allowed.')),
          const SizedBox(
            height: 8.0,
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                        maxLines: null,
                        decoration: InputDecoration(
                          errorText: msg.isEmpty ? null : msg,
                        ),
                        controller: controller,
                        autofocus: true)
                    .workaroundFreezeLinuxMint(),
              ),
            ],
          ),
        ],
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        dialogButton('Clear', onPressed: () async {
          await bind.mainSetOption(key: _kLeapgateOptionAllowNets, value: '');
          close();
        }, isOutline: true),
        dialogButton(
          'OK',
          onPressed: () async {
            final items = controller.text
                .split(RegExp(r'[\s,]+'))
                .where((s) => s.isNotEmpty)
                .toList();
            for (final item in items) {
              if (!_leapgateIsNet(item)) {
                setState(() {
                  msg =
                      '${translate('Invalid IP address or CIDR network')} $item';
                });
                return;
              }
            }
            await bind.mainSetOption(
                key: _kLeapgateOptionAllowNets, value: items.join(','));
            close();
          },
        ),
      ],
      onCancel: close,
    );
  });
}
