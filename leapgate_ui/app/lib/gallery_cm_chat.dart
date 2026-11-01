part of 'gallery_main.dart';

// ---- M3: chat side panel of the connection manager (A-P3.html) -------------

const _cmChatTalk = [
  LgChatMessage(
    text: '你好，我帮你看一下打印机。',
    time: '14:02',
    mine: false,
    sender: '李四',
  ),
  LgChatMessage(text: '好的，谢谢！', time: '14:03', mine: true),
];

const _cmChatMore = [
  LgChatMessage(
    text: '你好，我帮你看一下打印机。',
    time: '14:02',
    mine: false,
    sender: '李四',
  ),
  LgChatMessage(text: '好的，谢谢！', time: '14:03', mine: true),
  LgChatMessage(
    text: '驱动好像没装全，我先重装一遍。',
    time: '14:05',
    mine: false,
    sender: '李四',
  ),
  LgChatMessage(text: '大概要两分钟。', time: '14:05', mine: false, sender: '李四'),
  LgChatMessage(text: '好的，我这边不动。', time: '14:06', mine: true),
  LgChatMessage(text: '装好了，再打印一页试试。', time: '14:08', mine: false, sender: '李四'),
  LgChatMessage(text: '可以了，打出来了。', time: '14:09', mine: true),
  LgChatMessage(
    text: '那我先断开了，有事再找我。',
    time: '14:09',
    mine: false,
    sender: '李四',
  ),
];

const _cmChatLong = [
  LgChatMessage(
    text:
        '打印机的驱动在公司共享盘的“设备”文件夹里，名字是“打印机驱动 v2”，'
        '里面还有一份安装说明，装之前先把旧的驱动卸载干净，再重新启动一次电脑。',
    time: '14:02',
    mine: false,
    sender: '李四',
  ),
  LgChatMessage(
    text:
        '收到，下载地址是 https://example.com/downloads/printer/driver/setup-2026-11-01.exe',
    time: '14:03',
    mine: true,
  ),
  LgChatMessage(
    text:
        'Please restart the computer after the installation has finished, '
        'otherwise the printer is not listed.',
    time: '14:04',
    mine: false,
    sender: 'Alexandra Konstantinopoulos-Wang',
  ),
];

/// The side panel with the chat in it.
Widget _cmChatSide({
  List<LgChatMessage> messages = _cmChatTalk,
  String draft = '',
  String? empty,
  bool readOnly = false,
}) => LgCmSidePanel(
  icon: LgIcons.chat,
  title: '聊天',
  child: LgCmChat(
    messages: messages,
    controller: TextEditingController(text: draft),
    placeholder: '输入消息',
    sendLabel: '发送',
    mineLabel: '我',
    theirsLabel: '对方',
    emptyText: empty,
    readOnly: readOnly,
    readOnlyText: '对方已断开连接',
    onSend: (_) {},
  ),
);

/// The window with the chat open, 700 × 500; [leftHalf] cuts the chat out of it
/// (380 × 500), as the mockup frames the read-only state.
Widget _cmChatWindow({
  List<LgChatMessage> messages = _cmChatTalk,
  String draft = '',
  String? empty,
  bool readOnly = false,
  bool leftHalf = false,
}) {
  final window = _cmWindow(
    width: kLgCmExpandedWidth,
    tabs: _cmTabs(_cmLi, LgCmKind.remote, gone: readOnly),
    side: _cmChatSide(
      messages: messages,
      draft: draft,
      empty: empty,
      readOnly: readOnly,
    ),
    panel: _cmPanel(
      header: _cmHeader(
        _cmLi,
        status: readOnly
            ? const LgCmStatusLine(phase: LgCmPhase.disconnected, label: '已断开')
            : null,
        sideButton: _cmChat(selected: true),
      ),
      body: readOnly ? null : _cmPerms(),
      actions: readOnly
          ? [
              const LgCmActionRow(
                actions: [LgCmAction(label: '关闭', onPressed: _noop)],
              ),
            ]
          : [_cmDisconnectRow()],
    ),
  );
  if (!leftHalf) return window;
  return SizedBox(
    width: kLgCmSideWidth,
    height: kLgCmHeight,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        maxWidth: kLgCmExpandedWidth,
        child: window,
      ),
    ),
  );
}

List<Specimen> _cmChatSpecimens() {
  const wide = Size(kLgCmExpandedWidth, kLgCmHeight);
  const half = Size(kLgCmSideWidth, kLgCmHeight);
  Specimen cm(
    String name,
    Size size,
    Widget Function() build, {
    Set<WidgetState> states = const {},
  }) => Specimen('cm', name, size, padding: 0, states: states, (_) => build());

  return [
    cm('chat', wide, _cmChatWindow),
    cm(
      'chat-draft',
      half,
      () => _cmChatWindow(draft: '我这就去看看', leftHalf: true),
    ),
    cm(
      'chat-focus',
      half,
      () => _cmChatWindow(draft: '我这就去看看', leftHalf: true),
      states: const {WidgetState.focused},
    ),
    cm(
      'chat-conversation',
      half,
      () => _cmChatWindow(messages: _cmChatMore, leftHalf: true),
    ),
    cm(
      'chat-empty',
      half,
      () => _cmChatWindow(messages: const [], empty: '暂无聊天消息', leftHalf: true),
    ),
    cm(
      'chat-long',
      half,
      () => _cmChatWindow(messages: _cmChatLong, leftHalf: true),
    ),
    cm(
      'chat-read-only',
      half,
      () => _cmChatWindow(readOnly: true, leftHalf: true),
    ),
    cm(
      'chat-read-only-draft',
      half,
      () => _cmChatWindow(
        messages: _cmChatMore,
        draft: '还没发出去的话',
        readOnly: true,
        leftHalf: true,
      ),
    ),
    cm('chat-read-only-window', wide, () => _cmChatWindow(readOnly: true)),
  ];
}
