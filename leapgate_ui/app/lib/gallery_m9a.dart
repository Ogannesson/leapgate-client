// The M9a part of the component gallery: the install page's components next to the P11 mockups
// of A-P11-安装.html and the local notice cards of A-P1.html. A part of gallery_main.dart, so
// that it shares its helpers. Only the designer edits it (`LEAPGATE.md` §10.18).

part of 'gallery_main.dart';

const _m9aPath = r'C:\Program Files\Leapgate';

/// A dialog over a dimmed ground, like the install frames: the scrim does not scroll, the dialog
/// keeps within the area less 24 px all round and scrolls its middle.
Widget _m9aStage(Widget dialog, {double width = 560, double height = 620}) =>
    Builder(
      builder: (context) => SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: LgTokens.of(context).colors.bg,
          child: LgDialogScrim(
            scrollable: false,
            onEscape: _noop,
            child: dialog,
          ),
        ),
      ),
    );

/// The install dialog in one of the states of the P11 frames. [en] is the English check frame;
/// [printer] the printer ticked ("远程打印" opened it); [sessions] the line that says what the
/// install will do to the running sessions; [fail] the error banner; [busy] the install running.
Widget _m9aDialog({
  bool en = false,
  String path = _m9aPath,
  LgPathTone tone = LgPathTone.normal,
  String? message,
  String? messageTooltip,
  bool printer = false,
  bool sessions = false,
  String? fail,
  bool busy = false,
  bool installEnabled = true,
  bool changeFocus = false,
  bool licenseLine = true,
}) {
  final locked = busy;
  return LgInstallDialog(
    title: _x(en, '安装 Leapgate', 'Install Leapgate'),
    pathRow: LgInstallPathRow(
      label: _x(en, '安装位置', 'Install location'),
      path: path,
      changeLabel: _x(en, '修改', 'Change'),
      changeSemanticLabel: _x(en, '修改安装位置', 'Change install location'),
      onChange: locked ? null : _noop,
      changeAutofocus: changeFocus,
      tone: tone,
      message: message,
      messageTooltip: messageTooltip,
    ),
    options: [
      LgOptionCheck(
        value: true,
        label: _x(en, '创建开始菜单快捷方式', 'Create Start menu shortcuts'),
        onChanged: locked ? null : (_) {},
      ),
      LgOptionCheck(
        value: true,
        label: _x(en, '创建桌面快捷方式', 'Create a desktop shortcut'),
        onChanged: locked ? null : (_) {},
      ),
      LgOptionCheck(
        value: printer,
        label: _x(en, '安装 Leapgate 打印机', 'Install the Leapgate printer'),
        description: _x(
          en,
          '远程控制本机时，对方在本机打印到“Leapgate Printer”的文件将发送到对方的设备上打印',
          'Files that a remote user prints to "Leapgate Printer" on this device are sent to '
              "the remote user's device for printing",
        ),
        onChanged: locked ? null : (_) {},
      ),
    ],
    license: licenseLine
        ? LgLicenseLine(
            before: _x(en, '开始安装即表示接受', 'By installing, you accept the '),
            link: _x(en, '许可协议', 'license agreement'),
            after: _x(en, '。', '.'),
            onOpen: _noop,
          )
        : null,
    banners: [
      if (sessions)
        LgInstallBanner(
          tone: LgTone.warning,
          text: _x(
            en,
            'Leapgate 将关闭并重新打开，所有会话和正在使用的出口、隧道都将断开。',
            'Leapgate will close and open again. All sessions and every exit or tunnel in use '
                'will disconnect.',
          ),
        ),
      if (fail != null) LgInstallBanner(tone: LgTone.error, text: fail),
    ],
    actions: [
      LgDialogAction(
        label: _x(en, '取消', 'Cancel'),
        onPressed: busy ? null : _noop,
      ),
      LgDialogAction(
        label: busy ? _x(en, '正在安装…', 'Installing…') : _x(en, '安装', 'Install'),
        kind: LgButtonKind.primary,
        icon: LgIcons.uac,
        iconSize: 18,
        busy: busy,
        isDefault: true,
        onPressed: installEnabled ? _noop : null,
      ),
    ],
  );
}

const _m9aFailShort =
    '安装失败：Installer path or name contains characters unsafe for cmd.exe';
const _m9aFailLong =
    '安装失败：Cannot install the EXE package over an existing MSI installation';

List<Specimen> _m9aSpecimens() {
  final list = <Specimen>[];

  // ---- the dialog: the frames of A-P11-安装.html ----------------------------------------
  void dialog(
    String name,
    Widget Function() build, {
    double height = 620,
    double width = 560,
    Set<WidgetState> states = const {},
  }) => list.add(
    Specimen(
      'install-dialog',
      name,
      Size(width, height),
      padding: 0,
      states: states,
      (_) => _m9aStage(build(), width: width, height: height),
    ),
  );

  dialog('default', () => _m9aDialog()); // p11-default-*
  dialog('printer', () => _m9aDialog(printer: true)); // p11-printer-light
  dialog('sessions', () => _m9aDialog(sessions: true)); // p11-sessions-light
  dialog(
    'path-changed', // p11-path-d-light
    () => _m9aDialog(path: r'D:\Tools\Leapgate'),
  );
  dialog(
    'path-long', // p11-path-long-light: the pointer is on the box, a tooltip shows the whole
    () => _m9aDialog(path: r'D:\工作资料\常用软件\远程工具\公司内部\Leapgate'),
    states: const {WidgetState.hovered},
  );
  dialog(
    'bad-network', // p11-bad-net-light
    () => _m9aDialog(
      path: r'Z:\Leapgate',
      tone: LgPathTone.error,
      message: '无法安装到网络位置或可移动磁盘。请选择本机磁盘上的文件夹。',
      installEnabled: false,
      changeFocus: true,
    ),
  );
  dialog(
    'bad-percent', // p11-bad-pct-light
    () => _m9aDialog(
      path: r'D:\100%\Leapgate',
      tone: LgPathTone.error,
      message: '路径中不能包含“%”。请选择其他位置。',
      installEnabled: false,
      changeFocus: true,
    ),
  );
  dialog(
    'bad-self', // p11-bad-self-light
    () => _m9aDialog(
      path: r'C:\Users\zhangsan\Downloads\leapgate-0.4.0\Leapgate',
      tone: LgPathTone.error,
      message: '无法安装到 Leapgate 当前所在的文件夹。请选择其他位置。',
      // p11-bad-self-light: the pointer is on the red line, which shows the folder.
      messageTooltip: r'C:\Users\zhangsan\Downloads\leapgate-0.4.0',
      installEnabled: false,
      changeFocus: true,
    ),
  );
  dialog(
    'warn-nonempty', // p11-warn-nonempty-light
    () => _m9aDialog(
      path: r'D:\Tools\Leapgate',
      tone: LgPathTone.warning,
      message: '此文件夹中的现有文件将在安装或卸载 Leapgate 时被删除',
    ),
  );
  dialog('busy', () => _m9aDialog(busy: true)); // p11-busy-light
  dialog(
    'uac-denied', // p11-uac-light
    () => _m9aDialog(fail: '未获得管理员权限，未安装。'),
  );
  dialog('fail', () => _m9aDialog(fail: _m9aFailShort)); // p11-fail-light
  dialog(
    'fail-long', // p11-fail-long-light
    () => _m9aDialog(fail: _m9aFailLong),
    height: 680,
  );
  dialog(
    // p11-min-light: the 960×600 window, 40 px of title bar gone
    'min',
    () => _m9aDialog(),
    height: 560,
  );
  dialog(
    // p11-min-scroll-light: sessions and a long failure do not fit, the middle scrolls
    'min-scroll',
    () => _m9aDialog(sessions: true, fail: _m9aFailLong),
    height: 560,
  );
  dialog('english', () => _m9aDialog(en: true)); // p11-en-light

  // ---- the parts --------------------------------------------------------------------------
  // The parts on the dialog's own ground (`--lg-float`), at the width of its middle (416).
  Widget col(List<Widget> kids, {double width = 448}) => Builder(
    builder: (context) => DecoratedBox(
      decoration: BoxDecoration(
        color: LgTokens.of(context).colors.float,
        borderRadius: BorderRadius.circular(LgRadius.r12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LgSpace.s4),
        child: SizedBox(
          width: width - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, k) in kids.indexed) ...[
                if (i > 0) const SizedBox(height: LgSpace.s4),
                k,
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget path(
    String p, {
    LgPathTone tone = LgPathTone.normal,
    String? message,
    bool greyed = false,
  }) => LgInstallPathRow(
    label: '安装位置',
    path: p,
    changeLabel: '修改',
    changeSemanticLabel: '修改安装位置',
    onChange: greyed ? null : _noop,
    tone: tone,
    message: message,
  );

  list
    ..add(
      Specimen(
        'install-path-row',
        'normal',
        const Size(480, 152),
        (_) => col([path(_m9aPath)]),
      ),
    )
    ..add(
      Specimen(
        'install-path-row',
        'long-cut-hover',
        const Size(480, 152),
        states: const {WidgetState.hovered},
        (_) => col([path(r'D:\工作资料\常用软件\远程工具\公司内部\Leapgate')]),
      ),
    )
    ..add(
      Specimen(
        'install-path-row',
        'warning',
        const Size(480, 182),
        (_) => col([
          path(
            r'D:\Tools\Leapgate',
            tone: LgPathTone.warning,
            message: '此文件夹中的现有文件将在安装或卸载 Leapgate 时被删除',
          ),
        ]),
      ),
    )
    ..add(
      Specimen(
        'install-path-row',
        'error',
        const Size(480, 182),
        (_) => col([
          path(
            r'Z:\Leapgate',
            tone: LgPathTone.error,
            message: '无法安装到网络位置或可移动磁盘。请选择本机磁盘上的文件夹。',
          ),
        ]),
      ),
    )
    ..add(
      Specimen(
        'install-path-row',
        'greyed',
        const Size(480, 152),
        (_) => col([path(_m9aPath, greyed: true)]),
      ),
    );

  Widget option(bool on, {bool described = false, bool disabled = false}) =>
      LgOptionCheck(
        value: on,
        label: described ? '安装 Leapgate 打印机' : '创建桌面快捷方式',
        description: described
            ? '远程控制本机时，对方在本机打印到“Leapgate Printer”的文件将发送到对方的设备上打印'
            : null,
        onChanged: disabled ? null : (_) {},
      );

  for (final on in [false, true]) {
    for (final e in _states.entries) {
      list.add(
        Specimen(
          'install-option',
          '${on ? 'on' : 'off'}-${e.key}',
          const Size(480, 112),
          states: e.value,
          (_) => col([option(on)]),
        ),
      );
    }
    list.add(
      Specimen(
        'install-option',
        '${on ? 'on' : 'off'}-disabled',
        const Size(480, 112),
        (_) => col([option(on, disabled: true)]),
      ),
    );
    list.add(
      Specimen(
        'install-option',
        '${on ? 'on' : 'off'}-described',
        const Size(480, 156),
        (_) => col([option(on, described: true)]),
      ),
    );
  }

  list
    ..add(
      Specimen(
        'install-license',
        'default',
        const Size(480, 102),
        (_) => col([
          const LgLicenseLine(
            before: '开始安装即表示接受',
            link: '许可协议',
            after: '。',
            onOpen: _noop,
          ),
        ]),
      ),
    )
    ..add(
      Specimen(
        'install-license',
        'focus',
        const Size(480, 102),
        states: _focus,
        (_) => col([
          const LgLicenseLine(
            before: '开始安装即表示接受',
            link: '许可协议',
            after: '。',
            onOpen: _noop,
          ),
        ]),
      ),
    )
    ..add(
      Specimen(
        'install-banner',
        'sessions',
        const Size(480, 156),
        (_) => col([
          const LgInstallBanner(
            tone: LgTone.warning,
            text: 'Leapgate 将关闭并重新打开，所有会话和正在使用的出口、隧道都将断开。',
          ),
        ]),
      ),
    )
    ..add(
      Specimen(
        'install-banner',
        'fail-long',
        const Size(480, 142),
        (_) => col([
          const LgInstallBanner(tone: LgTone.error, text: _m9aFailLong),
        ]),
      ),
    );

  // ---- the local notice card's button (p1-hint-*, p11-entry-light) ---------------------------
  Widget notice({
    required String text,
    LgTone tone = LgTone.info,
    required String action,
    LgIcons? icon,
    LgButtonKind kind = LgButtonKind.secondary,
    bool busy = false,
    String? error,
  }) => SizedBox(
    width: 192,
    child: LgLocalNotice(
      tone: tone,
      text: text,
      actionLabel: action,
      onAction: _noop,
      actionIcon: icon,
      actionKind: kind,
      actionBusy: busy,
      actionError: error,
    ),
  );

  const upgradeText = '已安装的 Leapgate 版本低于当前版本。';
  const installText =
      '本机被远程控制时，便携版可能无法正常工作，例如对方无法操作用户账户控制（UAC）窗口。建议安装 Leapgate。';
  list
    ..add(
      Specimen(
        'local-notice-install',
        'upgrade-shield',
        const Size(240, 190),
        (_) => notice(
          text: upgradeText,
          action: '升级',
          icon: LgIcons.uac,
          kind: LgButtonKind.primary,
        ),
      ),
    )
    ..add(
      Specimen(
        'local-notice-install',
        'upgrade-busy',
        const Size(240, 190),
        (_) => notice(
          text: upgradeText,
          action: '正在升级…',
          icon: LgIcons.uac,
          kind: LgButtonKind.primary,
          busy: true,
        ),
      ),
    )
    ..add(
      Specimen(
        'local-notice-install',
        'upgrade-failed',
        const Size(240, 250),
        (_) => notice(
          text: upgradeText,
          action: '升级',
          icon: LgIcons.uac,
          kind: LgButtonKind.primary,
          error:
              '升级失败：Installer path or name contains characters unsafe for cmd.exe',
        ),
      ),
    )
    ..add(
      Specimen(
        'local-notice-install',
        'install-arrow',
        const Size(240, 290),
        (_) => notice(
          text: installText,
          tone: LgTone.warning,
          action: '安装',
          icon: LgIcons.download,
          kind: LgButtonKind.primary,
        ),
      ),
    )
    ..add(
      Specimen(
        'local-notice-install',
        'default-unchanged',
        const Size(240, 210),
        (_) => notice(text: '安装后，对方远程控制本机时也能操作用户账户控制（UAC）窗口。', action: '安装'),
      ),
    );

  return list;
}
