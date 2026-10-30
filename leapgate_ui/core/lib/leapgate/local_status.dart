import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/platform_model.dart';
import 'bridge.dart';

enum ServiceStatus { ready, connecting, notReady, stopped }

/// This device's ID and whether it can accept connections, polled once a second the way
/// upstream's desktop home page does (`flutter/lib/desktop/pages/connection_page.dart`
/// `updateStatus`, `desktop_home_page.dart` `fetchID`). A stand-in for the M0 placeholder page;
/// the options model (M1) takes it over.
class LocalStatusModel extends ChangeNotifier {
  String id = '';
  ServiceStatus status = ServiceStatus.connecting;
  Timer? _timer;

  void start() {
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final id = await bind.mainGetMyId();
    final connect =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    // upstream kOptionStopService
    final stopped = await bind.mainGetOption(key: 'stop-service') == 'Y';
    final status = stopped
        ? ServiceStatus.stopped
        : switch (connect['status_num']) {
            1 => ServiceStatus.ready,
            0 => ServiceStatus.connecting,
            _ => ServiceStatus.notReady,
          };
    if (id != this.id && id.isNotEmpty) {
      lgBind.leapgateLog(level: 3, msg: 'leapgate ui: this device id $id');
    }
    if (id != this.id || status != this.status) {
      this.id = id;
      this.status = status;
      notifyListeners();
    }
  }
}
