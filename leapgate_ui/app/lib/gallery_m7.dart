// The M7a part of the component gallery: the file transfer view's components next to the P7
// mockups of A-P7-文件传输.html, A-P7-文件传输-菜单与其他状态.html and A-P7-文件传输-对话框.html.
// A part of gallery_main.dart, so that it shares its helpers. Only the designer edits it
// (`LEAPGATE.md` §10.15).

part of 'gallery_main.dart';

// ---- sample data -------------------------------------------------------------------

class _M7File {
  const _M7File(
    this.kind,
    this.name,
    this.modified,
    this.type,
    this.size, {
    this.link = false,
    this.hidden = false,
    this.selected = false,
  });

  final LgFileKind kind;
  final String name;
  final String modified;
  final String type;
  final String size;
  final bool link;
  final bool hidden;
  final bool selected;
}

List<_M7File> _m7Local(bool en) => [
  _M7File(LgFileKind.folder, _x(en, '家庭照片 2026', 'Family photos 2026'), '2026/10/20 21:14', _x(en, '文件夹', 'Folder'), ''),
  _M7File(LgFileKind.folder, _x(en, '旧照片', 'Old photos'), '2026/03/02 08:40', _x(en, '符号链接', 'Symbolic link'), '', link: true),
  _M7File(LgFileKind.folder, _x(en, '项目资料', 'Project files'), '2026/10/15 10:02', _x(en, '文件夹', 'Folder'), ''),
  _M7File(LgFileKind.file, _x(en, '安装包.zip', 'installer.zip'), '2026/10/18 19:55', _x(en, 'ZIP 文件', 'ZIP file'), '1.21 GB'),
  _M7File(LgFileKind.file, _x(en, '会议录音.m4a', 'meeting.m4a'), '2026/10/27 11:30', _x(en, 'M4A 文件', 'M4A file'), '48.2 MB'),
  _M7File(LgFileKind.file, _x(en, '年度报告.docx', 'annual-report.docx'), '2026/10/28 14:05', _x(en, 'DOCX 文件', 'DOCX file'), '2.4 MB', selected: true),
  _M7File(LgFileKind.file, _x(en, '预算.xlsx', 'budget.xlsx'), '2026/10/26 16:48', _x(en, 'XLSX 文件', 'XLSX file'), '86.5 KB', selected: true),
];

List<_M7File> _m7Remote(bool en) => [
  _M7File(LgFileKind.folder, _x(en, '照片', 'Photos'), '2026/10/12 09:30', _x(en, '文件夹', 'Folder'), ''),
  _M7File(LgFileKind.file, _x(en, '年度报告.docx', 'annual-report.docx'), '2026/09/30 18:22', _x(en, 'DOCX 文件', 'DOCX file'), '2.3 MB'),
  _M7File(LgFileKind.file, _x(en, '视频素材.mp4.digest', 'clip.mp4.digest'), '2026/10/22 15:41', _x(en, '未完成的传输', 'Incomplete transfer'), _x(en, '64 字节', '64 bytes')),
  _M7File(LgFileKind.file, _x(en, '视频素材.mp4.download', 'clip.mp4.download'), '2026/10/22 15:41', _x(en, '未完成的传输', 'Incomplete transfer'), '2.1 GB'),
  _M7File(LgFileKind.file, _x(en, '说明.txt', 'notes.txt'), '2026/10/05 11:20', _x(en, 'TXT 文件', 'TXT file'), '4 KB'),
];

// An ID of the identity colour group 6 (blue), as the mockup's 书房台式机 has.
const _m7Id = '456 789 123';

LgFileHeaderLabels _m7Labels(bool en) => LgFileHeaderLabels(
  name: _x(en, '名称', 'Name'),
  modified: _x(en, '修改日期', 'Date modified'),
  type: _x(en, '类型', 'Type'),
  size: _x(en, '大小', 'Size'),
  ascending: _x(en, '升序', 'ascending'),
  descending: _x(en, '降序', 'descending'),
);

List<Widget> _m7Drives(bool en, {bool loading = false}) => loading
    ? [LgMenuLoadingRow(_x(en, '正在读取…', 'Reading…'))]
    : const [
        LgMenuItem(label: 'C:', checked: true, onPressed: _noop),
        LgMenuItem(label: 'D:', checked: false, onPressed: _noop),
        LgMenuItem(label: 'E:', checked: false, onPressed: _noop),
      ];

Widget _m7Crumb(
  bool en,
  List<String> segments, {
  String? root,
  List<Widget>? menu,
}) => LgBreadcrumb(
  rootLabel: root ?? _x(en, '此电脑', 'This PC'),
  rootTip: root == null || root == '此电脑' || root == 'This PC'
      ? _x(en, '此电脑', 'This PC')
      : _x(en, '根文件夹', 'Root folder'),
  segments: segments,
  rootMenu: menu ?? _m7Drives(en),
  onRoot: _noop,
  onSegment: (_) {},
  onEdit: _noop,
);

LgFileNavRow _m7Nav(bool en, Widget path, {bool canGoUp = true, bool compact = false}) => LgFileNavRow(
  compact: compact,
  back: LgFileNavButton(icon: LgIcons.arrowL, label: _x(en, '后退（Alt+←）', 'Back (Alt+←)'), onPressed: _noop),
  up: LgFileNavButton(icon: LgIcons.arrowU, label: _x(en, '上一级（Alt+↑）', 'Up (Alt+↑)'), onPressed: canGoUp ? _noop : null),
  home: LgFileNavButton(icon: LgIcons.home, label: _x(en, '主文件夹', 'Home folder'), onPressed: _noop),
  refresh: LgFileNavButton(icon: LgIcons.refresh, label: _x(en, '刷新（F5）', 'Refresh (F5)'), onPressed: _noop),
  path: path,
);

/// The row of actions of one pane, with a search field that this holder owns.
class _M7Ops extends StatefulWidget {
  const _M7Ops({
    required this.local,
    required this.en,
    this.transferEnabled = true,
    this.deleteEnabled = true,
    this.newFolderEnabled = true,
    this.search = '',
    this.open = false,
    this.compact = false,
  });

  final bool local;
  final bool en;
  final bool transferEnabled;
  final bool deleteEnabled;
  final bool newFolderEnabled;
  final String search;

  /// A narrow pane's field is open at the start.
  final bool open;
  final bool compact;

  @override
  State<_M7Ops> createState() => _M7OpsState();
}

class _M7OpsState extends State<_M7Ops> {
  late final _controller = TextEditingController(text: widget.search);
  final _focus = FocusNode();
  late bool _open = widget.open;

  // The exporter shows one specimen after another in the same place, so that the State outlives
  // them: the text and the flag have to follow the specimen.
  @override
  void didUpdateWidget(_M7Ops oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search) _controller.text = widget.search;
    if (oldWidget.open != widget.open) _open = widget.open;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.en;
    return LgFileOpRow(
      compact: widget.compact,
      searchOpen: _open,
      onSearchOpenChanged: (v) => setState(() => _open = v),
      searchActiveLabel: _x(en, '搜索当前文件夹，正在过滤', 'Search this folder, filtering'),
      actions: [
        LgButton(
          label: widget.local ? _x(en, '上传', 'Upload') : _x(en, '下载', 'Download'),
          kind: LgButtonKind.primary,
          icon: widget.local ? null : LgIcons.arrowL,
          trailingIcon: widget.local ? LgIcons.arrowR : null,
          onPressed: widget.transferEnabled ? _noop : null,
        ),
        LgListToolButton(
          icon: LgIcons.folderPlus,
          label: _x(en, '新建文件夹', 'New folder'),
          onPressed: widget.newFolderEnabled ? _noop : null,
        ),
        LgListToolButton(
          icon: LgIcons.trash,
          label: _x(en, '删除', 'Delete'),
          onPressed: widget.deleteEnabled ? _noop : null,
        ),
        LgMenuAnchor(
          items: [
            LgMenuItem(label: _x(en, '显示隐藏的项目', 'Show hidden items'), checked: false, onPressed: _noop),
            LgMenuItem(label: _x(en, '全选', 'Select all'), shortcut: 'Ctrl+A', onPressed: _noop),
          ],
          builder: (context, controller) => LgIconButton(
            icon: LgIcons.more,
            label: _x(en, '更多', 'More'),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
      ],
      searchController: _controller,
      searchFocusNode: _focus,
      searchPlaceholder: _x(en, '搜索当前文件夹', 'Search this folder'),
      searchClearLabel: _x(en, '清除搜索', 'Clear search'),
      searchOpenLabel: _x(en, '搜索当前文件夹', 'Search this folder'),
    );
  }
}

enum _M7List { normal, reading, empty, none, openFailed }

/// A whole pane built of the components, for the states of the mockup's `.col`.
Widget _m7Pane({
  required bool local,
  bool en = false,
  double width = 618,
  double height = 580,
  List<String>? segments,
  String? status,
  List<_M7File>? files,
  _M7List list = _M7List.normal,
  String? banner,
  LgDropState drop = LgDropState.none,
  String? dropMessage,
  bool dropFramed = true,
  bool readingDim = true,
  int? dropRow,
  bool transferEnabled = true,
  bool selection = true,
  String search = '',
  bool linux = false,
  bool editing = false,
  bool platformKnown = true,
  bool upDisabled = false,
  bool compact = false,
  bool searchOpen = false,
  bool? showTypeColumn,
}) {
  final rows = files ?? (local ? _m7Local(en) : _m7Remote(en));
  final showType = showTypeColumn ?? width >= 520;
  final path = segments ??
      (local
          ? ['C:', 'Users', 'zhangsan', 'Documents']
          : ['D:', _x(en, '备份', 'Backup')]);
  final selected = rows.where((r) => r.selected && selection).toList();
  final text = status ??
      (selected.isEmpty
          ? _x(en, '${rows.length} 个项目', '${rows.length} items')
          : _x(en, '已选择 ${selected.length} 个项目，2.48 MB', '${selected.length} items selected, 2.48 MB'));
  final labels = _m7Labels(en);
  Widget listArea;
  switch (list) {
    case _M7List.empty:
    case _M7List.none:
      final none = list == _M7List.none;
      listArea = Column(
        children: [
          LgFileListHeader(labels: labels, sortColumn: LgFileColumn.name, ascending: true, onSort: (_) {}, showType: showType),
          Expanded(
            child: Center(
              child: LgEmptyState(
                none
                    ? _x(en, '未找到匹配的项目', 'No matching items')
                    : _x(en, '此文件夹为空', 'This folder is empty'),
                icon: none ? LgIcons.search : LgIcons.folder,
              ),
            ),
          ),
        ],
      );
    case _M7List.openFailed:
      listArea = Column(
        children: [
          LgFileListHeader(labels: labels, sortColumn: LgFileColumn.name, ascending: true, onSort: (_) {}, showType: showType),
          Expanded(
            child: Center(
              child: Builder(
                builder: (context) => LgEmptyState(
                  _x(en, '无法打开“备份”：没有访问权限。', 'Can’t open “Backup”: access denied.'),
                  icon: LgIcons.err,
                  iconColor: LgTokens.of(context).colors.error,
                  iconBackground: LgTokens.of(context).colors.errorBg,
                  secondaryActionLabel: _x(en, '转到主文件夹', 'Go to home folder'),
                  onSecondaryAction: _noop,
                  actionLabel: _x(en, '重试', 'Retry'),
                  onAction: _noop,
                ),
              ),
            ),
          ),
        ],
      );
    case _M7List.normal:
    case _M7List.reading:
      listArea = LgReadingOverlay(
        reading: list == _M7List.reading,
        dim: readingDim,
        label: _x(en, '正在读取…', 'Reading…'),
        child: Column(
          children: [
            LgFileListHeader(labels: labels, sortColumn: LgFileColumn.name, ascending: true, onSort: (_) {}, showType: showType, onResize: (c, d) {}),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
                // A list that is cut at the pane's edge, as a scrolled one is (the smallest
                // window shows fewer rows than the specimens have).
                child: ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    for (final (i, f) in rows.indexed)
                      LgFileRow(
                        kind: f.kind,
                        name: f.name,
                        modified: f.modified,
                        type: f.type,
                        size: f.size,
                        link: f.link,
                        hidden: f.hidden,
                        selected: f.selected && selection,
                        dropTarget: dropRow == i,
                        showType: showType,
                        topDivider: i > 0 &&
                            !(f.selected && selection) &&
                            !(rows[i - 1].selected && selection),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
  }
  final pane = LgFilePaneFrame(
    semanticLabel: local ? _x(en, '本机', 'This device') : _x(en, '远程设备', 'Remote device'),
    child: Column(
      children: [
        LgFilePaneHeader(
          compact: compact,
          title: local ? _x(en, '本机', 'This device') : _x(en, '远程设备', 'Remote device'),
          subtitle: local
              ? 'LAPTOP-ZHANGSAN'
              : _x(en, '书房台式机 · ${linux ? 'Linux' : 'Windows'}', 'Study desktop · ${linux ? 'Linux' : 'Windows'}'),
          platform: local
              ? LgPlatform.windows
              : (platformKnown ? (linux ? LgPlatform.linux : LgPlatform.windows) : null),
          remoteId: local ? null : _m7Id,
        ),
        _m7Nav(
          en,
          editing
              ? LgTextField(
                  controller: TextEditingController(text: r'D:\备份\2025'),
                  semanticLabel: _x(en, '路径', 'Path'),
                  dense: true,
                  quiet: true,
                  errorText: _x(en, r'未找到“D:\备份\2025”。', r'“D:\Backup\2025” was not found.'),
                  showErrorText: false,
                )
              : _m7Crumb(
                  en,
                  linux ? const [] : path,
                  root: linux ? '/' : null,
                  menu: linux ? const [LgMenuItem(label: '/', checked: true, onPressed: _noop)] : null,
                ),
          canGoUp: !upDisabled && !(linux && path.isEmpty),
          compact: compact,
        ),
        if (banner != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(LgSpace.s3, 0, LgSpace.s3, LgSpace.s2),
            child: LgBanner(
              tone: LgTone.error,
              slim: true,
              dense: true,
              text: banner,
              dismissLabel: _x(en, '关闭', 'Dismiss'),
              onDismiss: _noop,
            ),
          ),
        _M7Ops(
          local: local,
          en: en,
          transferEnabled: transferEnabled && selected.isNotEmpty,
          deleteEnabled: selected.isNotEmpty,
          search: search,
          open: searchOpen,
          compact: compact,
        ),
        Expanded(child: listArea),
        LgFileStatusRow(text),
      ],
    ),
  );
  return SizedBox(
    width: width,
    height: height,
    child: LgDropZone(
      state: drop,
      framed: dropFramed,
      message: dropMessage,
      child: pane,
    ),
  );
}

// ---- the queue --------------------------------------------------------------------

LgQueueAction _m7Cancel(bool en) => LgQueueAction(icon: LgIcons.x, label: _x(en, '取消', 'Cancel'), onPressed: _noop);
LgQueueAction _m7Remove(bool en) => LgQueueAction(icon: LgIcons.x, label: _x(en, '移除', 'Remove'), onPressed: _noop);

/// A queue row with the sentence a screen reader gets, written here the way the page's owner
/// writes it: direction, name, then the state, in the language's punctuation.
LgQueueRow _m7Row({
  required bool en,
  required LgQueueDirection direction,
  required String name,
  required String path,
  required LgQueueState state,
  required String status,
  String? statusLead,
  double? progress,
  List<LgQueueAction> actions = const [],
  String? detailsLabel,
  bool detailsOpen = false,
  VoidCallback? onToggleDetails,
  List<LgQueueDetail> details = const [],
}) {
  final dir = switch (direction) {
    LgQueueDirection.upload => _x(en, '上传', 'Upload'),
    LgQueueDirection.download => _x(en, '下载', 'Download'),
    LgQueueDirection.delete => _x(en, '删除', 'Delete'),
  };
  final lead = statusLead == null ? '' : _x(en, '$statusLead，', '$statusLead, ');
  return LgQueueRow(
    direction: direction,
    semanticLabel: _x(en, '$dir $name，$lead$status', '$dir $name, $lead$status'),
    name: name,
    path: path,
    state: state,
    status: status,
    statusLead: statusLead,
    progress: progress,
    actions: actions,
    detailsLabel: detailsLabel,
    detailsOpen: detailsOpen,
    onToggleDetails: onToggleDetails,
    details: details,
  );
}

List<Widget> _m7QueueRows(bool en, {int count = 12, bool details = true}) {
  final rows = <Widget>[
    _m7Row(
      en: en,
      direction: LgQueueDirection.download,
      name: _x(en, '照片', 'Photos'),
      path: r'D:\备份\照片 → C:\Users\zhangsan\Pictures',
      state: LgQueueState.inProgress,
      statusLead: '45%',
      status: _x(en, '610 MB / 1.32 GB · 3 / 12 个文件 · 1.2 MB/s · 剩余约 10 分钟', '610 MB / 1.32 GB · 3 / 12 files · 1.2 MB/s · about 10 min left'),
      progress: .45,
      actions: [
        LgQueueAction(icon: LgIcons.pause, label: _x(en, '暂停', 'Pause'), onPressed: _noop),
        _m7Cancel(en),
      ],
    ),
    _m7Row(
      en: en,
      direction: LgQueueDirection.upload,
      name: _x(en, '安装包.zip', 'installer.zip'),
      path: r'C:\Users\zhangsan\Downloads → D:\备份',
      state: LgQueueState.queued,
      status: _x(en, '排队中', 'Queued'),
      actions: [_m7Cancel(en)],
    ),
    _m7Row(
      en: en,
      direction: LgQueueDirection.download,
      name: _x(en, '旧照片', 'Old photos'),
      path: r'D:\备份\旧照片 → C:\Users\zhangsan\Pictures',
      state: LgQueueState.counting,
      status: _x(en, '正在统计文件…', 'Counting files…'),
      actions: [_m7Cancel(en)],
    ),
    _m7Row(
      en: en,
      direction: LgQueueDirection.upload,
      name: _x(en, '年度报告.docx', 'annual-report.docx'),
      path: r'C:\Users\zhangsan\Documents → D:\备份',
      state: LgQueueState.waitingConfirm,
      status: _x(en, '等待确认：目标位置已有同名文件', 'Awaiting confirmation: a file with the same name is at the destination'),
    ),
    _m7Row(
      en: en,
      direction: LgQueueDirection.delete,
      name: _x(en, '临时', 'temp'),
      path: r'D:\备份\临时',
      state: LgQueueState.deleting,
      status: _x(en, '正在删除… 37 / 120 个文件', 'Deleting… 37 of 120 files'),
      progress: .31,
      actions: [_m7Cancel(en)],
    ),
    _m7Row(
      en: en,
      direction: LgQueueDirection.upload,
      name: _x(en, '视频素材.mp4', 'clip.mp4'),
      path: r'C:\Users\zhangsan\Videos → D:\备份',
      state: LgQueueState.paused,
      status: _x(en, '已暂停 · 已传 2.1 GB / 4.8 GB', 'Paused · 2.1 GB of 4.8 GB transferred'),
      progress: .44,
      actions: [
        LgQueueAction(icon: LgIcons.play, label: _x(en, '继续', 'Resume'), onPressed: _noop),
        _m7Cancel(en),
      ],
    ),
    _m7Row(
      en: en,
      direction: LgQueueDirection.upload,
      name: _x(en, '项目资料备份', 'Project backup'),
      path: r'C:\Users\zhangsan\Documents → D:\备份',
      state: LgQueueState.interrupted,
      status: _x(en, '已中断，重新连接后将继续', 'Interrupted, will resume after reconnecting'),
      actions: [_m7Cancel(en)],
    ),
    _m7Row(
      en: en,
      direction: LgQueueDirection.upload,
      name: _x(en, '预算.xlsx', 'budget.xlsx'),
      path: r'C:\Users\zhangsan\Documents → D:\备份',
      state: LgQueueState.done,
      status: _x(en, '已完成 · 1 个文件，86.5 KB', 'Completed · 1 file, 86.5 KB'),
      actions: [_m7Remove(en)],
    ),
    _m7Row(
      en: en,
      direction: LgQueueDirection.upload,
      name: _x(en, '项目资料', 'Project files'),
      path: r'C:\Users\zhangsan\Documents → D:\备份',
      state: LgQueueState.doneWithIssues,
      status: _x(en, '已完成，2 个文件未传输', 'Completed, 2 files not transferred'),
      detailsLabel: _x(en, '查看详情', 'Details'),
      detailsOpen: details,
      onToggleDetails: _noop,
      details: [
        LgQueueDetail(_x(en, r'项目资料\草稿.docx', r'Project files\draft.docx'), reason: _x(en, '没有访问权限', 'Access is denied')),
        LgQueueDetail(_x(en, r'项目资料\图表.png', r'Project files\chart.png'), reason: _x(en, '文件正被其他应用使用', 'File is in use by another app')),
      ],
      actions: [
        LgQueueAction(icon: LgIcons.refresh, label: _x(en, '重试未传输的文件', 'Retry files not transferred'), onPressed: _noop),
        _m7Remove(en),
      ],
    ),
    _m7Row(
      en: en,
      direction: LgQueueDirection.upload,
      name: _x(en, '说明.txt', 'notes.txt'),
      path: r'C:\Users\zhangsan\Documents → D:\备份',
      state: LgQueueState.skipped,
      status: _x(en, '已跳过：目标位置已有同名文件', 'Skipped: a file with the same name is at the destination'),
      actions: [_m7Remove(en)],
    ),
    _m7Row(
      en: en,
      direction: LgQueueDirection.download,
      name: _x(en, '视频', 'Videos'),
      path: r'D:\备份\视频 → C:\Users\zhangsan\Videos',
      state: LgQueueState.cancelled,
      status: _x(en, '已取消', 'Canceled'),
      actions: [_m7Remove(en)],
    ),
    _m7Row(
      en: en,
      direction: LgQueueDirection.upload,
      name: _x(en, '会议录音.m4a', 'meeting.m4a'),
      path: r'C:\Users\zhangsan\Documents → D:\备份',
      state: LgQueueState.failed,
      status: _x(en, '失败：文件正被其他应用使用', 'Failed: file is in use by another app'),
      actions: [
        LgQueueAction(icon: LgIcons.refresh, label: _x(en, '重试', 'Retry'), onPressed: _noop),
        _m7Remove(en),
      ],
    ),
  ];
  return rows.take(count).toList();
}

LgQueuePanel _m7Queue(
  bool en, {
  int count = 12,
  bool expanded = true,
  bool details = true,
  bool grip = true,
  List<LgQueueSpan>? spans,
  double? progress = .24,
  String? percent = '24%',
  String? emptyText,
  List<LgQueueSummaryAction>? actions,
}) => LgQueuePanel(
  title: _x(en, '传输', 'Transfers'),
  spans: spans ??
      [
        LgQueueSpan(_x(en, '3 个进行中，1 个排队，', '3 in progress, 1 queued, ')),
        LgQueueSpan(_x(en, '1 个失败', '1 failed'), tone: LgQueueTone.error),
        const LgQueueSpan('，'),
        LgQueueSpan(_x(en, '1 个等待确认', '1 awaiting confirmation'), tone: LgQueueTone.warning),
      ],
  progress: progress,
  percentText: percent,
  emptyText: emptyText,
  expanded: expanded,
  toggleLabel: expanded ? _x(en, '收起', 'Collapse') : _x(en, '展开', 'Expand'),
  onToggle: _noop,
  actions: actions ??
      [
        LgQueueSummaryAction(label: _x(en, '全部继续', 'Resume all'), icon: LgIcons.play, onPressed: _noop),
        LgQueueSummaryAction(label: _x(en, '清除已完成', 'Clear completed'), onPressed: _noop),
      ],
  rows: _m7QueueRows(en, count: count, details: details),
  onResize: grip ? (_) {} : null,
);

/// M7b's rows: all skipped, a delete that left items, details over the 50 shown, a paused row
/// with the 4 GB note.
List<Widget> _m7bQueueRows(bool en) => [
  _m7Row(
    en: en,
    direction: LgQueueDirection.download,
    name: _x(en, '照片', 'Photos'),
    path: r'D:\备份\照片 → C:\Users\zhangsan\Pictures',
    state: LgQueueState.doneWithIssues,
    status: _x(en, '已完成，2 个文件已跳过', 'Completed, 2 files skipped'),
    detailsLabel: _x(en, '查看详情', 'Details'),
    detailsOpen: true,
    onToggleDetails: _noop,
    details: [
      LgQueueDetail(_x(en, r'照片\IMG_0101.jpg · 已跳过：目标位置已有同名文件', r'Photos\IMG_0101.jpg · Skipped: a file with the same name is at the destination')),
      LgQueueDetail(_x(en, r'照片\IMG_0102.jpg · 已跳过：目标位置已有同名文件', r'Photos\IMG_0102.jpg · Skipped: a file with the same name is at the destination')),
    ],
    actions: [_m7Remove(en)],
  ),
  _m7Row(
    en: en,
    direction: LgQueueDirection.delete,
    name: _x(en, '临时', 'temp'),
    path: r'D:\备份\临时',
    state: LgQueueState.doneWithIssues,
    status: _x(en, '已完成，1 个项目未删除', 'Completed, 1 item not deleted'),
    detailsLabel: _x(en, '查看详情', 'Details'),
    detailsOpen: true,
    onToggleDetails: _noop,
    details: [
      LgQueueDetail(_x(en, r'临时\日志.txt', r'temp\log.txt'), reason: _x(en, '文件正被其他应用使用', 'The file is in use by another app')),
    ],
    actions: [
      LgQueueAction(icon: LgIcons.refresh, label: _x(en, '重试', 'Retry'), onPressed: _noop),
      _m7Remove(en),
    ],
  ),
  _m7Row(
    en: en,
    direction: LgQueueDirection.upload,
    name: _x(en, '素材库', 'Library'),
    path: r'C:\Users\zhangsan\Videos → D:\备份',
    state: LgQueueState.doneWithIssues,
    status: _x(en, '已完成，53 个文件未传输', 'Completed, 53 files not transferred'),
    detailsLabel: _x(en, '查看详情', 'Details'),
    detailsOpen: true,
    onToggleDetails: _noop,
    details: [
      for (var i = 1; i <= 3; i++)
        LgQueueDetail(_x(en, '素材库\\片段$i.mov', 'Library\\clip$i.mov'), reason: _x(en, '没有访问权限', 'Access is denied')),
      LgQueueDetail(_x(en, '另有 50 个文件', '50 more files')),
    ],
    actions: [
      LgQueueAction(icon: LgIcons.refresh, label: _x(en, '重试未传输的文件', 'Retry files not transferred'), onPressed: _noop),
      _m7Remove(en),
    ],
  ),
  _m7Row(
    en: en,
    direction: LgQueueDirection.download,
    name: _x(en, '系统镜像.iso', 'system.iso'),
    path: r'D:\备份 → C:\Users\zhangsan\Downloads',
    state: LgQueueState.paused,
    status: _x(en, '已暂停 · 已传 4.6 GB / 6.2 GB', 'Paused · 4.6 GB of 6.2 GB transferred'),
    progress: .74,
    detailsOpen: true,
    details: [
      LgQueueDetail(_x(en, '当前文件超过 4 GB，无法断点续传，将从头传输。', "The current file is larger than 4 GB and can't be resumed. It will start over.")),
    ],
    actions: [
      LgQueueAction(icon: LgIcons.play, label: _x(en, '继续', 'Resume'), onPressed: _noop),
      _m7Cancel(en),
    ],
  ),
];

LgQueuePanel _m7bQueue(bool en) => LgQueuePanel(
  title: _x(en, '传输', 'Transfers'),
  spans: [LgQueueSpan(_x(en, '1 个已暂停', '1 paused'))],
  progress: null,
  percentText: null,
  expanded: true,
  toggleLabel: _x(en, '收起', 'Collapse'),
  onToggle: _noop,
  actions: [
    LgQueueSummaryAction(label: _x(en, '全部继续', 'Resume all'), icon: LgIcons.play, onPressed: _noop),
    LgQueueSummaryAction(label: _x(en, '清除已完成', 'Clear completed'), onPressed: _noop),
  ],
  rows: _m7bQueueRows(en),
  onResize: (_) {},
);

// ---- the specimens ------------------------------------------------------------------

Widget _m7ViewSwitch(bool en, {double? progress, bool alert = false, bool highlighted = true}) =>
    LgToolbarMenuButton(
      label: _x(en, '文件传输', 'File transfer'),
      icon: LgIcons.folder,
      highlighted: highlighted,
      progress: progress,
      alert: alert,
      items: _m7ViewMenu(en),
    );

List<Widget> _m7ViewMenu(bool en, {bool alert = false}) => [
  LgMenuItem(
    label: _x(en, '远程桌面', 'Remote desktop'),
    icon: LgIcons.monitor,
    trailing: const LgViewMenuTail(status: LgRouteMark(route: LgRoute.direct, label: '直连')),
    onPressed: _noop,
  ),
  LgMenuItem(
    label: _x(en, '文件传输', 'File transfer'),
    icon: LgIcons.folder,
    trailing: LgViewMenuTail(
      progress: .45,
      percentText: '45%',
      alert: alert,
      status: LgRouteMark(route: LgRoute.direct, label: _x(en, '直连', 'Direct')),
    ),
    onPressed: _noop,
  ),
  LgMenuItem(label: _x(en, '终端', 'Terminal'), icon: LgIcons.terminal, hint: _x(en, '未打开', 'Not open'), onPressed: _noop),
  LgMenuItem(label: _x(en, '摄像头', 'Camera'), icon: LgIcons.camera, hint: _x(en, '未打开', 'Not open'), onPressed: _noop),
];

Widget _m7ViewBar(bool en, {double? progress, bool alert = false, bool route = true, bool compact = false, double width = 1100}) => SizedBox(
  width: width,
  child: LgViewBar(
    compact: compact,
    viewSwitch: _m7ViewSwitch(en, progress: progress, alert: alert),
    route: route
        ? LgToolbarRouteButton(
            route: LgRoute.direct,
            label: _x(en, '直连', 'Direct'),
            onPressed: _noop,
          )
        : null,
    disconnectLabel: _x(en, '断开', 'Disconnect'),
    onDisconnect: _noop,
  ),
);

/// The content of the 960 × 600 window under its tabs (`.frame.mn` of the mockup): the view bar,
/// the two panes and the queue, in the smallest window's measures: the page's 4 / 8 / 8 padding and
/// its 4 gap, the panes 8 apart, every row one step lower.
Widget _m7MinWindow({required bool expanded, bool en = false}) => Builder(
  builder: (context) => SizedBox(
    width: 960,
    height: 560,
    child: ColoredBox(
      color: LgTokens.of(context).colors.bg,
      child: Column(
        children: [
          _m7ViewBar(en, progress: .45, compact: true, width: 960),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(LgSpace.s2, LgSpace.s1, LgSpace.s2, LgSpace.s2),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _m7Pane(local: true, en: en, width: double.infinity, height: double.infinity, compact: true, showTypeColumn: false)),
                        const SizedBox(width: LgSpace.s2),
                        Expanded(child: _m7Pane(local: false, en: en, width: double.infinity, height: double.infinity, compact: true, selection: false, showTypeColumn: false)),
                      ],
                    ),
                  ),
                  const SizedBox(height: LgSpace.s1),
                  SizedBox(
                    height: expanded ? 190 : 44,
                    child: _m7Queue(
                      en,
                      count: 3,
                      expanded: expanded,
                      grip: expanded,
                      spans: [LgQueueSpan(_x(en, expanded ? '1 个进行中，2 个排队' : '1 个进行中', expanded ? '1 in progress, 2 queued' : '1 in progress'))],
                      progress: .45,
                      percent: '45%',
                      actions: const [],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

Widget _m7Tabs({double? progress, bool alert = false, int selected = 1}) => Builder(
  builder: (context) => SizedBox(
    width: 900,
    child: ColoredBox(
      color: LgTokens.of(context).colors.bg,
      child: LgTitleBar(
        labels: _labels,
        sessions: [
          LgSessionTab(
            name: '书房台式机',
            identity: 5,
            status: const LgRouteMark(route: LgRoute.direct, label: '直连'),
            progress: progress,
            alert: alert,
            markLabel: alert ? '有替换确认等待处理' : '文件传输 45%',
          ),
          const LgSessionTab(
            name: '妈妈的笔记本',
            identity: 4,
            status: LgRouteMark(route: LgRoute.relay, label: '经中继'),
          ),
        ],
        selected: selected,
        homeBadge: 1,
        maximized: false,
        onSelect: (_) {},
        onCloseTab: (_) {},
        onNewTab: _noop,
        onMinimize: _noop,
        onToggleMaximize: _noop,
        onClose: _noop,
        onStartDrag: _noop,
        onStartResize: (_) {},
      ),
    ),
  ),
);

Widget _m7Chip(String label, int count, {bool rejected = false}) =>
    LgDragChip(label: label, count: count, rejected: rejected);

List<Specimen> _m7Specimens() {
  final list = <Specimen>[];
  void add(String section, String name, Size size, WidgetBuilder b, {Set<WidgetState> states = const {}, double padding = 16}) =>
      list.add(Specimen(section, name, size, b, states: states, padding: padding));

  // The view bar and its switch -------------------------------------------------------
  for (final en in [false, true]) {
    final sfx = en ? '-english' : '';
    add('file-view-bar', 'default$sfx', const Size(1132, 84), (_) => _m7ViewBar(en));
    add('file-view-bar', 'progress$sfx', const Size(1132, 84), (_) => _m7ViewBar(en, progress: .45));
  }
  add('file-view-bar', 'compact', const Size(1132, 84), (_) => _m7ViewBar(false, progress: .45, compact: true));
  add('file-view-bar', 'alert', const Size(1132, 84), (_) => _m7ViewBar(false, alert: true));
  add('file-view-bar', 'hover', const Size(1132, 84), (_) => _m7ViewBar(false, progress: .45), states: const {WidgetState.hovered});
  // The smallest window, bar to queue: where the rows get a step lower (mockup `.frame.mn`).
  add('file-min-window', 'queue-folded', const Size(992, 592), (_) => _m7MinWindow(expanded: false));
  add('file-min-window', 'queue-expanded', const Size(992, 592), (_) => _m7MinWindow(expanded: true));
  add('file-view-bar', 'connecting', const Size(1132, 84), (_) => _m7ViewBar(false, route: false));
  add(
    'file-view-bar',
    'menu-open',
    const Size(380, 240),
    (_) => LgMenuPanel(width: 340, items: _m7ViewMenu(false)),
  );
  add(
    'file-view-bar',
    'menu-open-alert',
    const Size(380, 240),
    (_) => LgMenuPanel(width: 340, items: _m7ViewMenu(false, alert: true)),
  );
  add(
    'file-view-bar',
    'switch-open',
    const Size(300, 84),
    (_) => _m7ViewSwitch(false, progress: .45),
    states: const {WidgetState.selected},
  );

  // Marks on the tabs --------------------------------------------------------------------
  add('file-tab', 'ring', const Size(932, 72), (_) => _m7Tabs(progress: .45));
  add('file-tab', 'ring-selected-other', const Size(932, 72), (_) => _m7Tabs(progress: .45, selected: 2));
  add('file-tab', 'reminder', const Size(932, 72), (_) => _m7Tabs(alert: true));
  add(
    'file-ring',
    'values',
    const Size(300, 56),
    (_) => const Row(
      children: [
        LgProgressRing(value: 0),
        SizedBox(width: 12),
        LgProgressRing(value: .25),
        SizedBox(width: 12),
        LgProgressRing(value: .5),
        SizedBox(width: 12),
        LgProgressRing(value: .99),
        SizedBox(width: 12),
        LgReminderMark(),
      ],
    ),
  );

  // The pane's parts ----------------------------------------------------------------------
  for (final en in [false, true]) {
    final sfx = en ? '-english' : '';
    add(
      'file-pane-header',
      'local-and-remote$sfx',
      // Three headers of the spacious mode's 48 px and two 8 px gaps, in the padding.
      const Size(682, 192),
      (_) => SizedBox(
        width: 650,
        child: Column(
          children: [
            LgFilePaneFrame(
              child: LgFilePaneHeader(
                title: _x(en, '本机', 'This device'),
                subtitle: 'LAPTOP-ZHANGSAN',
                platform: LgPlatform.windows,
              ),
            ),
            const SizedBox(height: 8),
            LgFilePaneFrame(
              child: LgFilePaneHeader(
                title: _x(en, '远程设备', 'Remote device'),
                subtitle: _x(en, '书房台式机 · Windows', 'Study desktop · Windows'),
                platform: LgPlatform.windows,
                remoteId: _m7Id,
              ),
            ),
            const SizedBox(height: 8),
            LgFilePaneFrame(
              child: LgFilePaneHeader(
                title: _x(en, '远程设备', 'Remote device'),
                subtitle: '',
              ),
            ),
          ],
        ),
      ),
    );
  }
  add(
    'file-pane-header',
    'platforms',
    const Size(682, 192),
    (_) => SizedBox(
      width: 650,
      child: Column(
        spacing: 8,
        children: [
          for (final (p, id) in [
            (LgPlatform.linux, '234 567 891'),
            (LgPlatform.macos, '345 678 912'),
            (LgPlatform.android, '456 789 123'),
          ])
            LgFilePaneFrame(
              child: LgFilePaneHeader(title: '远程设备', subtitle: '客厅迷你主机 · ${p.name}', platform: p, remoteId: id),
            ),
        ],
      ),
    ),
  );

  Widget navCard(Widget Function() path, {bool canGoUp = true, bool en = false, double width = 650}) =>
      SizedBox(width: width, child: LgFilePaneFrame(child: _m7Nav(en, path(), canGoUp: canGoUp)));
  add('file-path', 'short', const Size(682, 76), (_) => navCard(() => _m7Crumb(false, ['C:', 'Users', 'zhangsan', 'Documents'])));
  add('file-path', 'root', const Size(682, 76), (_) => navCard(() => _m7Crumb(false, const []), canGoUp: false));
  add('file-path', 'folded', const Size(682, 76), (_) => navCard(() => _m7Crumb(false, ['D:', '备份', '2026', '十月', '家庭', '照片', '原图']), width: 520));
  add('file-path', 'half-window', const Size(500, 76), (_) => navCard(() => _m7Crumb(false, ['C:', 'Users', 'zhangsan', 'Documents']), width: 468));
  add('file-path', 'icon-root-folded', const Size(417, 76), (_) => navCard(() => _m7Crumb(false, ['C:', 'Users', 'zhangsan', 'Documents']), width: 385));
  add('file-path', 'narrowest', const Size(360, 76), (_) => navCard(() => _m7Crumb(false, ['C:', 'Users', 'zhangsan', 'Documents']), width: 327.6));
  add('file-path', 'folded-narrow', const Size(682, 76), (_) => navCard(() => _m7Crumb(false, ['C:', 'Users', 'zhangsan', 'Documents', '工作文件夹']), width: 420));
  add('file-path', 'linux-root', const Size(682, 76), (_) => navCard(() => _m7Crumb(false, const [], root: '/', menu: const [LgMenuItem(label: '/', checked: true, onPressed: _noop)]), canGoUp: false));
  add('file-path', 'this-pc-english', const Size(682, 76), (_) => navCard(() => _m7Crumb(true, ['C:', 'Users', 'zhangsan', 'Documents']), en: true));
  add('file-path', 'drives-open', const Size(260, 180), (_) => LgMenuPanel(width: 216, items: _m7Drives(false)));
  add('file-path', 'drives-loading', const Size(260, 112), (_) => LgMenuPanel(width: 216, items: _m7Drives(false, loading: true)));
  // The focus is forced on the field alone: forcing it on a whole row would ring its buttons too.
  add(
    'file-path',
    'input',
    const Size(482, 64),
    (_) => SizedBox(
      width: 434,
      child: LgTextField(
        controller: TextEditingController(text: r'D:\备份\照片'),
        semanticLabel: '路径',
        dense: true,
        quiet: true,
      ),
    ),
    states: const {WidgetState.focused},
  );
  add(
    'file-path',
    'input-error',
    const Size(682, 120),
    (_) => Stack(
      clipBehavior: Clip.none,
      children: [
        navCard(
          () => LgTextField(
            controller: TextEditingController(text: r'D:\备份\2025'),
            semanticLabel: '路径',
            dense: true,
            quiet: true,
            errorText: r'未找到“D:\备份\2025”。',
            showErrorText: false,
          ),
        ),
        const Positioned(left: 144, top: 56, child: LgPathError(r'未找到“D:\备份\2025”。')),
      ],
    ),
  );

  // The row of actions, narrow and wide -------------------------------------------------
  Widget opCard(Widget ops, {double width = 618}) => SizedBox(width: width, child: LgFilePaneFrame(child: ops));
  for (final (name, local, enabled) in [
    ('upload', true, true),
    ('upload-disabled', true, false),
    ('download', false, true),
    ('download-disabled', false, false),
  ]) {
    add('file-ops', name, const Size(650, 76), (_) => opCard(_M7Ops(local: local, en: false, transferEnabled: enabled, deleteEnabled: enabled)));
  }
  // The tests lay text out in a face with square glyphs, where English runs about a third wider
  // than in Atkinson: the English row gets 80 px more than the mockup's pane so that it passes.
  add('file-ops', 'upload-english', const Size(730, 76), (_) => opCard(const _M7Ops(local: true, en: true), width: 698));
  add('file-ops', 'search-text', const Size(650, 76), (_) => opCard(const _M7Ops(local: true, en: false, search: '报告')));
  add('file-ops', 'collapsed', const Size(520, 76), (_) => opCard(const _M7Ops(local: true, en: false), width: 468));
  // Collapsed with something typed: the icon is in the accent colour on a tint.
  add('file-ops', 'collapsed-filtering', const Size(520, 76), (_) => opCard(const _M7Ops(local: true, en: false, search: '报告'), width: 468));
  add('file-ops', 'collapsed-open', const Size(520, 76), (_) => opCard(const _M7Ops(local: true, en: false, search: '报告', open: true), width: 468));
  add('file-ops', 'collapsed-icon-tools', const Size(336, 76), (_) => opCard(const _M7Ops(local: true, en: false), width: 304));
  add('file-ops', 'collapsed-english', const Size(520, 76), (_) => opCard(const _M7Ops(local: true, en: true), width: 468));
  add('file-ops', 'compact', const Size(650, 76), (_) => opCard(const _M7Ops(local: true, en: false, compact: true)));
  add('file-ops', 'new-folder-off', const Size(650, 76), (_) => opCard(const _M7Ops(local: true, en: false, newFolderEnabled: false, transferEnabled: false)));

  // The list ----------------------------------------------------------------------------------
  add(
    'file-list',
    'header',
    const Size(682, 84),
    (_) => SizedBox(
      width: 650,
      child: Builder(
        builder: (context) => ColoredBox(
          color: LgTokens.of(context).colors.surface,
          child: LgFileListHeader(
            labels: _m7Labels(false),
            sortColumn: LgFileColumn.modified,
            ascending: false,
            onSort: (_) {},
            onResize: (c, d) {},
          ),
        ),
      ),
    ),
  );
  add(
    'file-list',
    'header-hover',
    const Size(682, 84),
    (_) => SizedBox(
      width: 650,
      child: Builder(
        builder: (context) => ColoredBox(
          color: LgTokens.of(context).colors.surface,
          child: LgFileListHeader(
            labels: _m7Labels(false),
            sortColumn: LgFileColumn.name,
            ascending: true,
            onSort: (_) {},
          ),
        ),
      ),
    ),
    states: const {WidgetState.hovered},
  );
  add(
    'file-list',
    'header-no-type',
    const Size(502, 84),
    (_) => SizedBox(
      width: 470,
      child: Builder(
        builder: (context) => ColoredBox(
          color: LgTokens.of(context).colors.surface,
          child: LgFileListHeader(
            labels: _m7Labels(false),
            sortColumn: LgFileColumn.name,
            ascending: true,
            onSort: (_) {},
            showType: false,
          ),
        ),
      ),
    ),
  );
  Widget rowsCard(List<LgFileRow> rows, {double width = 618}) => SizedBox(
    width: width,
    child: LgFilePaneFrame(
      child: Padding(
        padding: const EdgeInsets.all(LgSpace.s2),
        child: Column(children: rows),
      ),
    ),
  );
  add(
    'file-list',
    'rows',
    const Size(650, 340),
    (_) => rowsCard([
      const LgFileRow(kind: LgFileKind.folder, name: '项目资料', modified: '2026/10/15 10:02', type: '文件夹'),
      const LgFileRow(kind: LgFileKind.folder, name: '旧照片', modified: '2026/03/02 08:40', type: '符号链接', link: true, topDivider: true),
      const LgFileRow(kind: LgFileKind.file, name: 'desktop.ini', modified: '2026/01/05 09:00', type: 'INI 文件', size: '282 字节', hidden: true, topDivider: true),
      const LgFileRow(kind: LgFileKind.file, name: '视频素材.mp4.download', modified: '2026/10/22 15:41', type: '未完成的传输', size: '2.1 GB', topDivider: true),
      const LgFileRow(kind: LgFileKind.file, name: '一个名字很长很长很长很长很长很长很长很长很长很长很长的文件.docx', modified: '2026/10/22 15:41', type: 'DOCX 文件', size: '12.4 MB', topDivider: true),
      const LgFileRow(kind: LgFileKind.drive, name: 'C:', type: '驱动器', topDivider: true),
    ]),
  );
  add(
    'file-list',
    'row-states',
    const Size(650, 340),
    (_) => rowsCard([
      const LgFileRow(kind: LgFileKind.file, name: '年度报告.docx', modified: '2026/10/28 14:05', type: 'DOCX 文件', size: '2.4 MB', selected: true),
      const LgFileRow(kind: LgFileKind.file, name: '预算.xlsx', modified: '2026/10/26 16:48', type: 'XLSX 文件', size: '86.5 KB', selected: true, link: true),
      const LgFileRow(kind: LgFileKind.file, name: '会议录音.m4a', modified: '2026/10/27 11:30', type: 'M4A 文件', size: '48.2 MB', focused: true),
      const LgFileRow(kind: LgFileKind.folder, name: '照片', modified: '2026/10/12 09:30', type: '文件夹', dropTarget: true),
      const LgFileRow(kind: LgFileKind.file, name: '说明.txt', modified: '2026/10/05 11:20', type: 'TXT 文件', size: '4 KB', topDivider: true),
    ]),
  );
  add(
    'file-list',
    'row-hover',
    const Size(650, 100),
    (_) => rowsCard([
      const LgFileRow(kind: LgFileKind.file, name: '说明.txt', modified: '2026/10/05 11:20', type: 'TXT 文件', size: '4 KB'),
    ]),
    states: const {},
  );
  add(
    'file-list',
    'rows-no-type',
    const Size(502, 220),
    (_) => rowsCard([
      const LgFileRow(kind: LgFileKind.folder, name: '项目资料', modified: '2026/10/15 10:02', showType: false),
      const LgFileRow(kind: LgFileKind.file, name: '安装包.zip', modified: '2026/10/18 19:55', size: '1.21 GB', showType: false, topDivider: true),
      const LgFileRow(kind: LgFileKind.file, name: '年度报告.docx', modified: '2026/10/28 14:05', size: '2.4 MB', showType: false, selected: true),
    ], width: 470),
  );

  // The whole panes, in the states of the mockup ---------------------------------------------
  const paneSize = Size(650, 612);
  for (final en in [false, true]) {
    final sfx = en ? '-english' : '';
    final size = en ? const Size(730, 612) : paneSize;
    final width = en ? 698.0 : 618.0;
    add('file-pane', 'local$sfx', size, (_) => _m7Pane(local: true, en: en, width: width));
    add('file-pane', 'remote$sfx', size, (_) => _m7Pane(local: false, en: en, selection: false, width: width));
  }
  add('file-pane', 'remote-selected', paneSize, (_) => _m7Pane(local: false, files: [for (final f in _m7Remote(false)) f.name == '照片' ? const _M7File(LgFileKind.folder, '照片', '2026/10/12 09:30', '文件夹', '', selected: true) : f]));
  add('file-pane', 'reading', paneSize, (_) => _m7Pane(local: false, list: _M7List.reading, selection: false));
  add('file-pane', 'reading-same-folder', paneSize, (_) => _m7Pane(local: false, list: _M7List.reading, readingDim: false, selection: false));
  add(
    'file-pane',
    'banner',
    paneSize,
    (_) => _m7Pane(
      local: false,
      selection: false,
      banner: '无法打开“System Volume Information”：没有访问权限。',
      segments: const ['D:'],
      files: const [
        _M7File(LgFileKind.folder, '备份', '2026/10/12 09:30', '文件夹', ''),
        _M7File(LgFileKind.folder, '下载', '2026/09/18 20:05', '文件夹', ''),
        _M7File(LgFileKind.folder, '视频', '2026/10/10 12:48', '文件夹', ''),
        _M7File(LgFileKind.folder, 'System Volume Information', '2026/01/05 09:00', '文件夹', '', hidden: true),
      ],
    ),
  );
  add('file-pane', 'open-failed', paneSize, (_) => _m7Pane(local: false, list: _M7List.openFailed, selection: false, status: ''));
  add('file-pane', 'empty', paneSize, (_) => _m7Pane(local: false, list: _M7List.empty, selection: false, status: '0 个项目', segments: ['D:', '备份', '旧备份']));
  add('file-pane', 'no-results', paneSize, (_) => _m7Pane(local: false, list: _M7List.none, selection: false, search: 'zzz', status: '0 个项目'));
  add('file-pane', 'platform-unknown', paneSize, (_) => _m7Pane(local: false, platformKnown: false, selection: false));
  add('file-pane', 'linux-root', paneSize, (_) => _m7Pane(local: false, linux: true, segments: const [], files: [
    for (final n in ['bin', 'etc', 'home', 'mnt', 'tmp', 'usr', 'var'])
      _M7File(LgFileKind.folder, n, '2026/10/21 06:40', '文件夹', ''),
  ], selection: false));
  add('file-pane', 'this-pc', paneSize, (_) => _m7Pane(local: true, segments: const [], upDisabled: true, selection: false, transferEnabled: false, files: const [
    _M7File(LgFileKind.drive, 'C:', '', '驱动器', ''),
    _M7File(LgFileKind.drive, 'D:', '', '驱动器', ''),
    _M7File(LgFileKind.drive, 'E:', '', '驱动器', ''),
  ]));
  add('file-pane', 'narrow', const Size(500, 612), (_) => _m7Pane(local: true, width: 468));
  add('file-pane', 'path-editing', paneSize, (_) => _m7Pane(local: false, editing: true, selection: false));

  // Dragging ------------------------------------------------------------------------------------
  add(
    'file-drop',
    'accept',
    const Size(650, 612),
    (_) => Stack(
      children: [
        _m7Pane(local: false, selection: false, drop: LgDropState.accept, dropMessage: '上传到“备份”', status: '5 个项目'),
        Positioned(left: 330, top: 395, child: _m7Chip('年度报告.docx', 2)),
      ],
    ),
  );
  add(
    'file-drop',
    'folder-row',
    const Size(650, 612),
    (_) => Stack(
      children: [
        _m7Pane(local: false, selection: false, dropRow: 0, drop: LgDropState.accept, dropFramed: false, dropMessage: '上传到“照片”'),
        Positioned(left: 240, top: 232, child: _m7Chip('上传到“照片”', 2)),
      ],
    ),
  );
  add(
    'file-drop',
    'reject',
    const Size(650, 612),
    (_) => Stack(
      children: [
        _m7Pane(local: true, drop: LgDropState.reject),
        Positioned(left: 290, top: 450, child: _m7Chip('年度报告.docx', 2, rejected: true)),
      ],
    ),
  );
  add(
    'file-drop',
    'chips',
    // Three chips of 29 px in the spacious mode, two 12 px gaps, in the padding.
    const Size(420, 144),
    (_) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _m7Chip('年度报告.docx', 1),
        const SizedBox(height: 12),
        _m7Chip('年度报告.docx', 3),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.only(left: 16), child: _m7Chip('年度报告.docx', 2, rejected: true)),
      ],
    ),
  );

  // The queue -------------------------------------------------------------------------------------
  add('file-queue', 'expanded-all-states', const Size(1272, 596), (_) => SizedBox(width: 1240, height: 560, child: _m7Queue(false)));
  add('file-queue', 'expanded-all-states-english', const Size(1272, 596), (_) => SizedBox(width: 1240, height: 560, child: _m7Queue(true)));
  add('file-queue', 'm7b-states', const Size(1272, 520), (_) => SizedBox(width: 1240, height: 484, child: _m7bQueue(false)));
  add('file-queue', 'm7b-states-english', const Size(1272, 520), (_) => SizedBox(width: 1240, height: 484, child: _m7bQueue(true)));
  add('file-queue', 'folded', const Size(1272, 92), (_) => SizedBox(width: 1240, height: 52, child: _m7Queue(false, expanded: false, grip: false, spans: [const LgQueueSpan('1 个进行中')], progress: .45, percent: '45%', actions: const [])));
  add('file-queue', 'empty', const Size(1272, 92), (_) => SizedBox(width: 1240, height: 52, child: _m7Queue(false, expanded: false, grip: false, emptyText: '暂无传输任务', progress: null, percent: null, actions: const [])));
  add(
    'file-queue',
    'one-way-failure',
    const Size(1272, 180),
    (_) => SizedBox(
      width: 1240,
      height: 148,
      child: LgQueuePanel(
        title: '传输',
        spans: const [LgQueueSpan('1 个失败', tone: LgQueueTone.error)],
        expanded: true,
        toggleLabel: '收起',
        onToggle: _noop,
        actions: const [LgQueueSummaryAction(label: '清除已完成', onPressed: _noop)],
        rows: [
          LgQueueRow(
            direction: LgQueueDirection.download,
            semanticLabel: '下载 照片，失败：远程设备仅允许向其上传文件，不允许下载、删除、重命名或新建文件夹',
            name: '照片',
            path: r'D:\备份\照片 → C:\Users\zhangsan\Pictures',
            state: LgQueueState.failed,
            status: '失败：远程设备仅允许向其上传文件，不允许下载、删除、重命名或新建文件夹',
            actions: [_m7Remove(false)],
          ),
          LgQueueRow(
            direction: LgQueueDirection.upload,
            semanticLabel: '上传 预算.xlsx，已完成 · 1 个文件，86.5 KB',
            name: '预算.xlsx',
            path: r'C:\Users\zhangsan\Documents → D:\备份',
            state: LgQueueState.done,
            status: '已完成 · 1 个文件，86.5 KB',
            actions: [_m7Remove(false)],
          ),
        ],
      ),
    ),
  );
  add('file-queue', 'min-window-folded', const Size(968, 92), (_) => SizedBox(width: 936, height: 44, child: _m7Queue(false, expanded: false, grip: false, spans: [const LgQueueSpan('1 个进行中')], progress: .45, percent: '45%', actions: const [])));
  add('file-queue', 'min-window-expanded', const Size(968, 220), (_) => SizedBox(width: 936, height: 188, child: _m7Queue(false, count: 3, spans: [const LgQueueSpan('1 个进行中，2 个排队')], progress: .45, percent: '45%', actions: const [])));
  add('file-queue', 'min-window-details', const Size(968, 360), (_) => SizedBox(width: 936, height: 330, child: _m7Queue(false, count: 9)));
  add('file-queue', 'paused-rows', const Size(1272, 150), (_) => SizedBox(
    width: 1240,
    height: 118,
    child: LgQueuePanel(
      title: '传输',
      spans: const [LgQueueSpan('2 个已暂停')],
      expanded: true,
      toggleLabel: '收起',
      onToggle: _noop,
      actions: const [LgQueueSummaryAction(label: '全部继续', icon: LgIcons.play, onPressed: _noop)],
      rows: _m7QueueRows(false).where((r) => r is LgQueueRow && r.state == LgQueueState.paused).toList(),
    ),
  ));

  // The delete confirmation while the files are counted ----------------------------------
  add(
    'file-counting',
    'note',
    const Size(420, 80),
    (_) => const SizedBox(width: 388, child: LgCountingNote('正在统计要删除的项目…')),
  );

  // What the dialog and menu components were given for the M7a visual check ------------------
  // A confirmation with something at the start of its buttons (`d-rp-normal`: the plain-text
  // "取消传输" at the lower left, "跳过" and "替换" at the right), a form dialog without the
  // icon tile (`d-nf-ok`, `d-rn-ok`) and a menu row with the check mark (read as checked).
  for (final en in [false, true]) {
    final sfx = en ? '-english' : '';
    add(
      'dialog-parts-m7a',
      'confirm-leading$sfx',
      const Size(560, 340),
      padding: 0,
      (_) => _m6Stage(
        width: 560,
        height: 340,
        LgConfirmDialog(
          title: _x(en, '替换“年度报告.docx”？', 'Replace “annual-report.docx”?'),
          body: _x(en, '目标文件夹“D:\\备份”中已有同名文件。', 'The destination folder “D:\\Backup” already has a file with this name.'),
          width: 480,
          leading: LgButton(label: _x(en, '取消传输', 'Cancel transfer'), kind: LgButtonKind.text, onPressed: _noop),
          actions: [
            LgDialogAction(label: _x(en, '跳过', 'Skip'), onPressed: _noop),
            LgDialogAction(label: _x(en, '替换', 'Replace'), kind: LgButtonKind.primary, isDefault: true, onPressed: _noop),
          ],
          children: [
            LgCheckbox(value: false, label: _x(en, '对此次传输中的其他冲突执行相同操作', 'Do this for the other conflicts in this transfer'), onChanged: (_) {}),
          ],
        ),
      ),
    );
    add(
      'dialog-parts-m7a',
      'form-without-icon$sfx',
      const Size(520, 360),
      padding: 0,
      (_) => _m6Stage(
        width: 520,
        height: 360,
        LgFormDialog(
          title: _x(en, '新建文件夹', 'New folder'),
          note: _x(en, '位置：远程设备 · D:\\备份', 'Location: Remote device · D:\\Backup'),
          actions: [
            LgDialogAction(label: _x(en, '取消', 'Cancel'), onPressed: _noop),
            LgDialogAction(label: _x(en, '新建', 'Create'), kind: LgButtonKind.primary, isDefault: true, onPressed: _noop),
          ],
          children: [
            LgFormField(
              label: _x(en, '名称', 'Name'),
              child: LgTextField(controller: TextEditingController(text: _x(en, '新建文件夹', 'New folder')), semanticLabel: _x(en, '名称', 'Name')),
            ),
          ],
        ),
      ),
    );
    add(
      'dialog-parts-m7a',
      'form-without-icon-or-note$sfx',
      const Size(520, 320),
      padding: 0,
      (_) => _m6Stage(
        width: 520,
        height: 320,
        LgFormDialog(
          title: _x(en, '重命名“年度报告.docx”', 'Rename “annual-report.docx”'),
          actions: [
            LgDialogAction(label: _x(en, '取消', 'Cancel'), onPressed: _noop),
            LgDialogAction(label: _x(en, '重命名', 'Rename'), kind: LgButtonKind.primary, isDefault: true, onPressed: _noop),
          ],
          children: [
            LgFormField(
              label: _x(en, '名称', 'Name'),
              child: LgTextField(controller: TextEditingController(text: _x(en, 'annual-report final.docx', 'annual-report final.docx')), semanticLabel: _x(en, '名称', 'Name')),
            ),
          ],
        ),
      ),
    );
  }
  add(
    'dialog-parts-m7a',
    'menu-checked-row',
    const Size(260, 256),
    (_) => const LgMenuPanel(
      width: 216,
      items: [
        LgMenuGroup('排序方式'),
        LgMenuItem(label: '名称', checked: true, onPressed: _noop),
        LgMenuItem(label: '修改日期', checked: false, onPressed: _noop),
        LgMenuItem(label: '类型', checked: false, onPressed: _noop),
        LgMenuItem(label: '大小', checked: false, onPressed: _noop),
      ],
    ),
  );
  return list;
}
