// Leapgate application exit (phase 4): the exit node directory from the connection page menu.
// Only advice: any device ID can be tried as an exit, the exit itself decides.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

void showLeapgateExitNodes(BuildContext context) {
  // Fetched once per opening, never polled.
  final exits = bind.mainGetCommon(key: 'leapgate-exits');
  gFFI.dialogManager.show((setState, close, dialogContext) {
    return CustomAlertDialog(
      title: Text(translate('Exit nodes')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<String>(
            future: exits,
            builder: (_, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              return _body(context, close, snapshot.data ?? '');
            },
          ),
          const SizedBox(height: 12),
          Text(translate(
              'You can also enter a device ID, open TCP tunneling and add an exit node')),
        ],
      ),
      actions: [dialogButton('Close', onPressed: close)],
      onSubmit: close,
      onCancel: close,
    );
  }, clickMaskDismiss: true, backDismiss: true);
}

Widget _body(BuildContext context, VoidCallback close, String json) {
  Map<String, dynamic> m;
  try {
    m = jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    m = const {};
  }
  final list = m['exits'] is List ? m['exits'] as List : const [];
  final String? message = switch (m['state']) {
    'unsupported' =>
      'The current server does not provide an exit node directory',
    'not_logged_in' => 'Log in to see the exit nodes you can use',
    'ok' when list.isEmpty => 'No exit node is available right now',
    'ok' => null,
    _ => 'Failed to load the exit node list',
  };
  if (message != null) return Text(translate(message));
  return ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 360),
    child: ListView(
      shrinkWrap: true,
      children: list.map((e) {
        final id = e['id'] as String? ?? '';
        final hostname = e['hostname'] as String? ?? '';
        final owner = e['owner'] as String? ?? '';
        final own = e['own'] == true;
        final subtitle = [
          id,
          if (own) translate('Mine') else if (owner.isNotEmpty) owner,
        ].join(' · ');
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(hostname.isEmpty ? id : hostname),
          subtitle: Text(subtitle),
          trailing: dialogButton('Use', onPressed: () {
            close();
            connect(context, id, isTcpTunneling: true);
          }),
        );
      }).toList(),
    ),
  );
}
