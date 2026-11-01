// 上游：flutter/lib/models/cm_file_model.dart@bd9262397（改写：日志的解析和每条记录的状态规则照抄（`_dealOneJob`、`_onFileRemove` 删目录时去掉其下的删除记录、未读数加减）；`parent`、`gFFI` 换成构造时给的 `ServerModel`；"侧栏正显示这个连接的记录"由页面设 `shownConnId`，代替上游读标签控制器和聊天 model；记录表按连接在第一条日志到时建（上游在标签被选中时建，没选中过的连接的日志会被丢掉）；Rx 换成 ChangeNotifier；速度、`display()` 这些只给上游界面用的删掉；重命名记下原路径和新名字两项，不拼成一行。上游这个文件改了，合并时人工比对）
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'file_model.dart';
import 'server_model.dart';

/// What each visitor's file transfer session did on this device, for the connection manager's
/// file log (01 §3.3). The `cm_file_transfer_log` events feed it.
class CmFileModel with ChangeNotifier {
  CmFileModel(this.serverModel);

  final ServerModel serverModel;
  final _jobTables = <int, List<CmFileLog>>{};

  /// The connection whose log the side panel shows; its records are not counted as unread.
  int? shownConnId;

  /// Oldest first.
  List<CmFileLog> logOf(int connId) =>
      List.unmodifiable(_jobTables[connId] ?? const <CmFileLog>[]);

  List<CmFileLog> _table(int connId) => _jobTables.putIfAbsent(connId, () => []);

  void onFileTransferLog(Map<String, dynamic> evt) {
    if (evt['transfer'] != null) {
      _onFileTransfer(evt['transfer']);
    } else if (evt['remove'] != null) {
      _onFileRemove(evt['remove']);
    } else if (evt['create_dir'] != null) {
      _onDirCreate(evt['create_dir']);
    } else if (evt['rename'] != null) {
      _onRename(evt['rename']);
    }
    notifyListeners();
  }

  _onFileTransfer(dynamic log) {
    try {
      dynamic d = jsonDecode(log);
      if (d is List<dynamic>) {
        for (var l in d) {
          _dealOneJob(l);
        }
      } else {
        _dealOneJob(d);
      }
    } catch (e) {
      debugPrint("onFileTransferLog:$e");
    }
  }

  _dealOneJob(dynamic l) {
    final data = TransferJobSerdeData.fromJson(l);
    var jobTable = _table(data.connId);
    CmFileLog? job = jobTable.firstWhereOrNull((e) => e.id == data.id);
    if (job == null) {
      job = CmFileLog();
      jobTable.add(job);
      _addUnread(data.connId);
    }
    job.id = data.id;
    job.action =
        data.isRemote ? CmFileAction.remoteToLocal : CmFileAction.localToRemote;
    job.fileName = data.path;
    job.totalSize = data.totalSize;
    job.finishedSize = data.finishedSize;
    if (job.finishedSize > data.totalSize) {
      job.finishedSize = data.totalSize;
    }

    if (job.finishedSize > 0) {
      if (job.finishedSize < job.totalSize) {
        job.state = JobState.inProgress;
      } else {
        job.state = JobState.done;
      }
    }
    if (data.done) {
      job.state = JobState.done;
    } else if (data.cancel || data.error == 'skipped') {
      job.state = JobState.done;
      job.err = 'skipped';
    } else if (data.error.isNotEmpty) {
      job.state = JobState.error;
      job.err = data.error;
    }
  }

  _onFileRemove(dynamic log) {
    try {
      dynamic d = jsonDecode(log);
      FileActionLog data = FileActionLog.fromJson(d);
      Client? client =
          serverModel.clients.firstWhereOrNull((e) => e.id == data.connId);
      var jobTable = _table(data.connId);
      int removeUnreadCount = 0;
      if (data.dir) {
        bool isChild(String parent, String child) {
          if (child.startsWith(parent) && child.length > parent.length) {
            final suffix = child.substring(parent.length);
            return suffix.startsWith('/') || suffix.startsWith('\\');
          }
          return false;
        }

        removeUnreadCount = jobTable
            .where((e) =>
                e.action == CmFileAction.remove &&
                isChild(data.path, e.fileName))
            .length;
        jobTable.removeWhere((e) =>
            e.action == CmFileAction.remove && isChild(data.path, e.fileName));
      }
      jobTable.add(CmFileLog()
        ..id = data.id
        ..fileName = data.path
        ..action = CmFileAction.remove
        ..state = JobState.done);
      if (shownConnId != data.connId) {
        // Wrong number if unreadCount changes during deletion, which rarely happens
        RxInt? rx = client?.unreadChatMessageCount;
        if (rx != null) {
          if (rx.value >= removeUnreadCount) {
            rx.value -= removeUnreadCount;
          }
          rx.value += 1;
        }
      }
    } catch (e) {
      debugPrint('$e');
    }
  }

  _onDirCreate(dynamic log) {
    try {
      dynamic d = jsonDecode(log);
      FileActionLog data = FileActionLog.fromJson(d);
      _table(data.connId).add(CmFileLog()
        ..id = data.id
        ..fileName = data.path
        ..action = CmFileAction.createDir
        ..state = JobState.done);
      _addUnread(data.connId);
    } catch (e) {
      debugPrint('$e');
    }
  }

  _onRename(dynamic log) {
    try {
      dynamic d = jsonDecode(log);
      FileRenamenLog data = FileRenamenLog.fromJson(d);
      _table(data.connId).add(CmFileLog()
        ..id = 0
        ..fileName = data.path
        ..newName = data.newName
        ..action = CmFileAction.rename
        ..state = JobState.done);
      _addUnread(data.connId);
    } catch (e) {
      debugPrint('$e');
    }
  }

  _addUnread(int connId) {
    Client? client =
        serverModel.clients.firstWhereOrNull((e) => e.id == connId);
    if (shownConnId != connId) {
      client?.unreadChatMessageCount.value += 1;
    }
  }
}

enum CmFileAction {
  none,
  remoteToLocal,
  localToRemote,
  remove,
  createDir,
  rename,
}

class CmFileLog {
  JobState state = JobState.none;
  var id = 0;
  var finishedSize = 0;
  var totalSize = 0;
  CmFileAction action = CmFileAction.none;

  /// The path on this device; for a rename the old one.
  var fileName = "";

  /// A rename's new name.
  var newName = "";
  var err = "";

  bool isTransfer() {
    return action == CmFileAction.remoteToLocal ||
        action == CmFileAction.localToRemote;
  }
}

class TransferJobSerdeData {
  int connId;
  int id;
  String path;
  bool isRemote;
  int totalSize;
  int finishedSize;
  int transferred;
  bool done;
  bool cancel;
  String error;

  TransferJobSerdeData({
    required this.connId,
    required this.id,
    required this.path,
    required this.isRemote,
    required this.totalSize,
    required this.finishedSize,
    required this.transferred,
    required this.done,
    required this.cancel,
    required this.error,
  });

  TransferJobSerdeData.fromJson(dynamic d)
      : this(
          connId: d['connId'] ?? 0,
          id: int.tryParse(d['id'].toString()) ?? 0,
          path: d['dataSource'] ?? '',
          isRemote: d['isRemote'] ?? false,
          totalSize: d['totalSize'] ?? 0,
          finishedSize: d['finishedSize'] ?? 0,
          transferred: d['transferred'] ?? 0,
          done: d['done'] ?? false,
          cancel: d['cancel'] ?? false,
          error: d['error'] ?? '',
        );
}

class FileActionLog {
  int id = 0;
  int connId = 0;
  String path = '';
  bool dir = false;

  FileActionLog({
    required this.connId,
    required this.id,
    required this.path,
    required this.dir,
  });

  FileActionLog.fromJson(dynamic d)
      : this(
          connId: d['connId'] ?? 0,
          id: d['id'] ?? 0,
          path: d['path'] ?? '',
          dir: d['dir'] ?? false,
        );
}

class FileRenamenLog {
  int connId = 0;
  String path = '';
  String newName = '';

  FileRenamenLog({
    required this.connId,
    required this.path,
    required this.newName,
  });

  FileRenamenLog.fromJson(dynamic d)
      : this(
          connId: d['connId'] ?? 0,
          path: d['path'] ?? '',
          newName: d['newName'] ?? '',
        );
}
