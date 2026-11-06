// 上游：flutter/lib/models/server_model.dart@bd9262397（只删界面调用，不格式化；只留连接管理小窗用到的部分，主窗口和 Android 的部分整段删掉：密码、ID、服务端连接状态、起停服务、Android 权限和亮屏、各权限开关、登录和语音对话框、showInputWarnAlert、showClientsMayNotBeChangedAlert；`tabController` 和 `jumpTo` 删掉，标签是页面自己的列表（app/lib/cm/）；`parent` 换成 `CmWindow`，`hideCmWindow`、`showCmWindow`、`windowOnTop(null)`、`windowManager.minimize`、`windowManager.close` 改调它（leapgate/cm_core.dart）；`isTest` 的两处判断删掉，计时器由 `dispose` 停；`_addTab` 里聊天的 `updateConnIdOfKey` 删掉：CM 的聊天按对方 ID 存、按所在标签的连接发（leapgate/cm_chat.dart），没有要更新的连接编号）
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../leapgate/cm_core.dart';

class ServerModel with ChangeNotifier {
  bool _showElevation = false;
  bool hideCm = false;
  String _approveMode = "";
  int _zeroClientLengthCounter = 0;

  final List<Client> _clients = [];

  Timer? cmHiddenTimer;

  bool get showElevation => _showElevation;

  String get approveMode => _approveMode;

  List<Client> get clients => _clients;

  final CmWindow window;

  // leapgate: kept so that dispose can stop it.
  Timer? _timer;

  ServerModel(this.window) {
    timerCallback() async {
      if (desktopType == DesktopType.cm) {
        final res = await bind.cmCheckClientsLength(length: _clients.length);
        if (res != null) {
          debugPrint("clients not match!");
          updateClientState(res);
        } else {
          if (_clients.isEmpty) {
            window.hide();
            if (_zeroClientLengthCounter++ == 12) {
              // 6 second
              window.close();
            }
          } else {
            _zeroClientLengthCounter = 0;
            if (!hideCm) window.show();
          }
        }
      }

      updatePasswordModel();
    }

      Future.delayed(Duration.zero, () async {
        if (await bind.optionSynced()) {
          await timerCallback();
        }
      });
      _timer = Timer.periodic(Duration(milliseconds: 500), (timer) async {
        await timerCallback();
      });
  }

  updatePasswordModel() async {
    var update = false;
    final approveMode = await bind.mainGetOption(key: kOptionApproveMode);
    if (_approveMode != approveMode) {
      _approveMode = approveMode;
      update = true;
    }
    if (update) {
      notifyListeners();
    }
  }

  // force
  updateClientState([String? json]) async {
    var res = await bind.cmGetClientsState();
    List<dynamic> clientsJson;
    try {
      clientsJson = jsonDecode(res);
    } catch (e) {
      debugPrint("Failed to decode clientsJson: '$res', error $e");
      return;
    }

    final oldClientLenght = _clients.length;
    _clients.clear();

    for (var clientJson in clientsJson) {
      try {
        final client = Client.fromJson(clientJson);
        _clients.add(client);
        _addTab(client);
      } catch (e) {
        debugPrint("Failed to decode clientJson '$clientJson', error $e");
      }
    }
    if (desktopType == DesktopType.cm) {
      if (_clients.isEmpty) {
        window.hide();
      } else if (!hideCm) {
        window.show();
      }
    }
    if (_clients.length != oldClientLenght) {
      notifyListeners();
    }
  }

  void addConnection(Map<String, dynamic> evt) {
    try {
      final client = Client.fromJson(jsonDecode(evt["client"]));
      if (client.authorized) {
        final index = _clients.indexWhere((c) => c.id == client.id);
        if (index < 0) {
          _clients.add(client);
        } else {
          if (_clients[index].authorized) {
            _clients[index].privacyMode = client.privacyMode;
            notifyListeners();
            return;
          }
          _clients[index].authorized = true;
          _clients[index].privacyMode = client.privacyMode;
        }
      } else {
        final index = _clients.indexWhere((c) => c.id == client.id);
        if (index >= 0) {
          _clients[index].privacyMode = client.privacyMode;
          notifyListeners();
          return;
        }
        _clients.add(client);
      }
      _addTab(client);
      // remove disconnected
      final index_disconnected = _clients
          .indexWhere((c) => c.disconnected && c.peerId == client.peerId);
      if (index_disconnected >= 0) {
        _clients.removeAt(index_disconnected);
      }
      if (desktopType == DesktopType.cm && !hideCm) {
        window.show();
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Failed to call loginRequest,error:$e");
    }
  }

  void _addTab(Client client) {
    Future.delayed(Duration.zero, () async {
      if (!hideCm) window.bringToFront();
    });
    // Only do the hidden task when on Desktop.
    if (client.authorized && isDesktop) {
      cmHiddenTimer = Timer(const Duration(seconds: 3), () {
        if (!hideCm) window.collapse();
        cmHiddenTimer = null;
      });
    }
  }

  handleVoiceCall(Client client, bool accept) {
    bind.cmHandleIncomingVoiceCall(id: client.id, accept: accept);
  }

  void sendLoginResponse(Client client, bool res) async {
    if (res) {
      bind.cmLoginRes(connId: client.id, res: res);
      client.authorized = true;
      notifyListeners();
    } else {
      bind.cmLoginRes(connId: client.id, res: res);
      _clients.remove(client);
    }
  }

  void onClientRemove(Map<String, dynamic> evt) {
    try {
      final id = int.parse(evt['id'] as String);
      final close = (evt['close'] as String) == 'true';
      if (_clients.any((c) => c.id == id)) {
        final index = _clients.indexWhere((client) => client.id == id);
        if (index >= 0) {
          if (close) {
            _clients.removeAt(index);
          } else {
            _clients[index].disconnected = true;
          }
        }
      }
      if (desktopType == DesktopType.cm && _clients.isEmpty) {
        window.hide();
        // leapgate: upstream closes here through its tab controller (`tabController.remove` →
        // `server_page.dart` `onRemoveId`). Left to the 6 s count, the closing window's `closeAll`
        // would end a visitor who reconnects about 6 s later.
        if (close) window.close();
      }
      notifyListeners();
    } catch (e) {
      debugPrint("onClientRemove failed,error:$e");
    }
  }

  /// `byOperator` false means the CM's window went away rather than a person asking for the
  /// peers to go. The sessions end either way; only the close reason differs, and with it
  /// whether the peer is allowed to reconnect. See `ipc::Data::CmWindowClosed`.
  Future<void> closeAll({bool byOperator = true}) async {
    await Future.wait(_clients.map((client) => byOperator
        ? bind.cmCloseConnection(connId: client.id)
        : bind.cmCloseConnectionWindow(connId: client.id)));
    _clients.clear();
  }

  void setShowElevation(bool show) {
    if (_showElevation != show) {
      _showElevation = show;
      notifyListeners();
    }
  }

  void updateVoiceCallState(Map<String, dynamic> evt) {
    try {
      final client = Client.fromJson(jsonDecode(evt["client"]));
      final index = _clients.indexWhere((element) => element.id == client.id);
      if (index != -1) {
        _clients[index].inVoiceCall = client.inVoiceCall;
        _clients[index].incomingVoiceCall = client.incomingVoiceCall;
        if (client.incomingVoiceCall) {
            // Has incoming phone call, let's set the window on top.
            Future.delayed(Duration.zero, () {
              window.bringToFront();
            });
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint("updateVoiceCallState failed: $e");
    }
  }

  // leapgate: the model lives as long as the CM's process; tests stop its timers.
  @override
  void dispose() {
    _timer?.cancel();
    cmHiddenTimer?.cancel();
    super.dispose();
  }
}

enum ClientType {
  remote,
  file,
  camera,
  portForward,
  terminal,
}

class Client {
  int id = 0; // client connections inner count id
  bool authorized = false;
  bool isFileTransfer = false;
  bool isViewCamera = false;
  bool isTerminal = false;
  String portForward = "";
  String name = "";
  String avatar = "";
  String peerId = ""; // peer user's id,show at app
  bool keyboard = false;
  bool clipboard = false;
  bool audio = false;
  bool file = false;
  bool restart = false;
  bool recording = false;
  bool blockInput = false;
  bool privacyMode = false;
  bool disconnected = false;
  bool fromSwitch = false;
  bool inVoiceCall = false;
  bool incomingVoiceCall = false;

  RxInt unreadChatMessageCount = 0.obs;

  Client(this.id, this.authorized, this.isFileTransfer, this.isViewCamera,
      this.name, this.peerId, this.keyboard, this.clipboard, this.audio);

  Client.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    authorized = json['authorized'];
    isFileTransfer = json['is_file_transfer'];
    // TODO: no entry then default.
    isViewCamera = json['is_view_camera'];
    isTerminal = json['is_terminal'] ?? false;
    portForward = json['port_forward'];
    name = json['name'];
    avatar = json['avatar'] ?? '';
    peerId = json['peer_id'];
    keyboard = json['keyboard'];
    clipboard = json['clipboard'];
    audio = json['audio'];
    file = json['file'];
    restart = json['restart'];
    recording = json['recording'];
    blockInput = json['block_input'];
    privacyMode = json['privacy_mode'] ?? privacyMode;
    disconnected = json['disconnected'];
    fromSwitch = json['from_switch'];
    inVoiceCall = json['in_voice_call'];
    incomingVoiceCall = json['incoming_voice_call'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['authorized'] = authorized;
    data['is_file_transfer'] = isFileTransfer;
    data['is_view_camera'] = isViewCamera;
    data['is_terminal'] = isTerminal;
    data['port_forward'] = portForward;
    data['name'] = name;
    data['avatar'] = avatar;
    data['peer_id'] = peerId;
    data['keyboard'] = keyboard;
    data['clipboard'] = clipboard;
    data['audio'] = audio;
    data['file'] = file;
    data['restart'] = restart;
    data['recording'] = recording;
    data['block_input'] = blockInput;
    data['privacy_mode'] = privacyMode;
    data['disconnected'] = disconnected;
    data['from_switch'] = fromSwitch;
    data['in_voice_call'] = inVoiceCall;
    data['incoming_voice_call'] = incomingVoiceCall;
    return data;
  }

  ClientType type_() {
    if (isFileTransfer) {
      return ClientType.file;
    } else if (isViewCamera) {
      return ClientType.camera;
    } else if (isTerminal) {
      return ClientType.terminal;
    } else if (portForward.isNotEmpty) {
      return ClientType.portForward;
    } else {
      return ClientType.remote;
    }
  }
}
