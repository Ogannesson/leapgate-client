// The M4 part of the component gallery: the account area, the login dialog, the
// address book (book switcher, tag filter, add-device dialog, tag colour dialog),
// the people of the team devices, the list states and the note of a device,
// next to the P1 mockups of A-P1.html (`p1-acct-*`, `p1-dlg-login*`,
// `p1-ab-*`, `p1-group`, `p1-st-*`, `p1-dlg-add*`, `p1-tagcolor-*`). A part of
// gallery_main.dart, so that it shares its helpers.

part of 'gallery_main.dart';

// ---- sample data and helpers -------------------------------------------------

const _m4Books = [
  LgBook(id: 'me', name: '我的地址簿', detail: '完全控制'),
  LgBook(id: 'home', name: '家里的电脑', detail: '可编辑 · 所有者：张三'),
  LgBook(id: 'friends', name: '朋友们', detail: '只读 · 所有者：李四'),
];

const _m4BooksEn = [
  LgBook(id: 'me', name: 'My address book', detail: 'Full control'),
  LgBook(
    id: 'home',
    name: 'Home computers',
    detail: 'Can edit · Owner: Zhang San',
  ),
  LgBook(id: 'friends', name: 'Friends', detail: 'Read only · Owner: Li Si'),
];

List<LgTagToggleItem> _m4TagItems(
  BuildContext context, {
  Set<String> on = const {},
  bool untagged = true,
  bool more = false,
}) {
  final c = LgTokens.of(context).colors;
  return [
    if (untagged)
      LgTagToggleItem(id: 'none', label: '未标记', on: on.contains('none')),
    LgTagToggleItem(
      id: 'home',
      label: '家里',
      color: c.identity[0].solid,
      on: on.contains('home'),
    ),
    LgTagToggleItem(
      id: 'work',
      label: '工作',
      color: c.identity[5].solid,
      on: on.contains('work'),
    ),
    LgTagToggleItem(
      id: 'common',
      label: '常用',
      color: c.identity[6].solid,
      on: on.contains('common'),
    ),
    if (more)
      for (final (i, name) in [
        '客厅',
        '卧室',
        '办公室',
        '服务器',
        '测试机',
        '朋友的电脑',
        '父母家',
        '临时',
      ].indexed)
        LgTagToggleItem(id: 'x$i', label: name, color: c.identity[i % 7].solid),
  ];
}

Widget _m4Panel(BuildContext context, Widget child, {double width = 224}) {
  final c = LgTokens.of(context).colors;
  return Container(
    width: width,
    padding: const EdgeInsets.all(LgSpace.s4),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(LgRadius.r16),
    ),
    child: child,
  );
}

List<Widget> _m4AccountMenu() => const [
  LgAccountMenuInfo(label: '账号信息', handle: '@zhangsan'),
  LgMenuItem(label: '退出登录', icon: LgIcons.logout, onPressed: _noop),
];

LgAccountArea _m4SignedIn({
  String initial = '张',
  String name = '张三',
  String handle = '@zhangsan',
}) => LgAccountArea.signedIn(
  initial: initial,
  name: name,
  handle: handle,
  menuItems: _m4AccountMenu(),
  semanticLabel: '账号：$name $handle',
);

const _m4LoginLabels = LgLoginDialogLabels(
  title: '登录',
  usernameLabel: '用户名',
  usernamePlaceholder: '输入用户名',
  passwordLabel: '密码',
  passwordPlaceholder: '输入密码',
  showPassword: '显示密码',
  hidePassword: '隐藏密码',
  cancel: '取消',
  submit: '登录',
  busySubmit: '正在登录…',
  retry: '重试',
);

const _m4LoginLabelsEn = LgLoginDialogLabels(
  title: 'Sign in',
  usernameLabel: 'Username',
  usernamePlaceholder: 'Enter your username',
  passwordLabel: 'Password',
  passwordPlaceholder: 'Enter your password',
  showPassword: 'Show password',
  hidePassword: 'Hide password',
  cancel: 'Cancel',
  submit: 'Sign in',
  busySubmit: 'Signing in…',
  retry: 'Retry',
);

const _m4AddLabels = LgAddDeviceLabels(
  title: '添加设备',
  idLabel: 'ID',
  idPlaceholder: '输入设备 ID',
  aliasLabel: '别名',
  aliasPlaceholder: '输入别名',
  passwordLabel: '密码',
  passwordPlaceholder: '输入密码',
  showPassword: '显示密码',
  hidePassword: '隐藏密码',
  noteLabel: '备注',
  notePlaceholder: '最多 300 字',
  tagsLabel: '标签',
  cancel: '取消',
  submit: '添加',
  busySubmit: '正在添加…',
);

const _m4AddLabelsEn = LgAddDeviceLabels(
  title: 'Add device',
  idLabel: 'ID',
  idPlaceholder: 'Enter the device ID',
  aliasLabel: 'Alias',
  aliasPlaceholder: 'Enter an alias',
  passwordLabel: 'Password',
  passwordPlaceholder: 'Enter the password',
  showPassword: 'Show password',
  hidePassword: 'Hide password',
  noteLabel: 'Note',
  notePlaceholder: 'Up to 300 characters',
  tagsLabel: 'Tags',
  cancel: 'Cancel',
  submit: 'Add',
  busySubmit: 'Adding…',
);

const _m4ColorLabels = LgTagColorDialogLabels(
  title: '修改标签颜色',
  colorLabel: '颜色',
  customLabel: '自定义',
  valueLabel: '颜色值',
  hexPlaceholder: '#RRGGBB',
  hexError: '颜色值格式不正确',
  brightnessLabel: '明度',
  wheelLabel: '色轮',
  cancel: '取消',
  save: '保存',
  busySave: '正在保存…',
);

const _m4ColorLabelsEn = LgTagColorDialogLabels(
  title: 'Change tag color',
  colorLabel: 'Color',
  customLabel: 'Custom',
  valueLabel: 'Color value',
  hexPlaceholder: '#RRGGBB',
  hexError: 'The color value is not valid',
  brightnessLabel: 'Brightness',
  wheelLabel: 'Color wheel',
  cancel: 'Cancel',
  save: 'Save',
  busySave: 'Saving…',
);

/// The address book page as `p1-ab-editable` draws it: the tabs and tools, the
/// book bar, the tag bar and cards.
Widget _m4BookPage(
  BuildContext context, {
  String selectedBook = 'home',
  Set<String> tagsOn = const {},
  bool notes = true,
  Widget? above,
  List<int> devices = const [0, 1, 3, 6, 7],
}) {
  final book = _m4Books.firstWhere((b) => b.id == selectedBook);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _listToolbar(selected: 3, sort: true, multi: false, refresh: true),
      // `.bk` 20 under the tabs, `.tgf` 12 under the book row, the cards 20
      // under the tags; the tag bar has 3 px of its own above and under.
      const SizedBox(height: LgSpace.s5),
      ?above,
      LgBookSwitcher(
        books: _m4Books,
        selectedId: book.id,
        onSelect: (_) {},
        searchPlaceholder: '搜索地址簿',
        noMatchLabel: '未找到匹配的地址簿',
        hint: '共享地址簿的成员和权限由管理员设置',
        semanticLabel: '切换地址簿',
        trailing: LgListToolMenu(
          icon: LgIcons.more,
          label: '更多',
          items: _m4MoreMenu(),
        ),
      ),
      const SizedBox(height: LgSpace.s3 - 3),
      LgTagFilterBar(
        items: _m4TagItems(context, on: tagsOn),
        onToggle: (_) {},
        onContextMenu: (_, _) {},
        noMenu: const {'none'},
        semanticLabel: '标签筛选',
      ),
      const SizedBox(height: LgSpace.s5 - 3),
      LgDeviceCardGrid(
        semanticLabel: '地址簿中的设备',
        children: [
          for (final (i, d) in devices.map((n) => _devices[n]).indexed)
            LgDeviceCard(
              name: d.name,
              id: d.id,
              platform: d.platform,
              status: d.status,
              statusLabel: d.statusLabel,
              userHost: d.userHost,
              note: notes && i == 4 ? '显卡驱动别升级' : null,
              tags: _tagsOf(context, i == 4 ? [1, 2] : [0]),
              favorite: i == 0,
              favoriteLabel: '已收藏',
              onTap: _noop,
              onDoubleTap: _noop,
            ),
        ],
      ),
    ],
  );
}

List<Widget> _m4MoreMenu({bool readOnly = false, bool synced = true}) => [
  if (!readOnly) ...[
    const LgMenuItem(label: '添加设备', onPressed: _noop),
    const LgMenuItem(label: '添加标签', onPressed: _noop),
  ],
  const LgMenuItem(label: '取消选择所有标签', onPressed: _noop),
  if (!readOnly)
    LgMenuCheckItem(label: '与最近会话同步', value: synced, onChanged: (_) {}),
  LgMenuCheckItem(label: '匹配全部所选标签', value: false, onChanged: (_) {}),
];

List<Specimen> _m4Specimens() {
  final list = <Specimen>[];
  const page = Size(1072, 500);

  // Account area ------------------------------------------------------------
  Specimen acct(
    String name,
    Widget Function(BuildContext) build, {
    Size size = const Size(256, 160),
    Set<WidgetState> states = const {},
  }) => Specimen(
    'account-area',
    name,
    size,
    states: states,
    (c) => _m4Panel(c, build(c)),
  );
  list
    ..add(
      acct(
        'signed-out',
        (_) => const LgAccountArea.signedOut(
          loginLabel: '登录',
          hint: '登录后可使用地址簿、同组设备和出口目录',
          onLogin: _noop,
        ),
        size: const Size(256, 190),
      ),
    )
    ..add(
      acct(
        'signed-out-english',
        (_) => const LgAccountArea.signedOut(
          loginLabel: 'Sign in',
          hint:
              'Sign in to use address books, team devices and the exit directory',
          onLogin: _noop,
        ),
        size: const Size(256, 220),
      ),
    )
    ..add(
      acct(
        'signed-out-hover',
        (_) => const LgAccountArea.signedOut(
          loginLabel: '登录',
          hint: '登录后可使用地址簿、同组设备和出口目录',
          onLogin: _noop,
        ),
        size: const Size(256, 190),
        states: _hover,
      ),
    )
    ..add(
      acct(
        'signed-out-focus',
        (_) => const LgAccountArea.signedOut(
          loginLabel: '登录',
          hint: '登录后可使用地址簿、同组设备和出口目录',
          onLogin: _noop,
        ),
        size: const Size(256, 190),
        states: _focus,
      ),
    )
    ..add(acct('signed-in', (_) => _m4SignedIn(), size: const Size(256, 130)))
    ..add(
      acct(
        'signed-in-hover',
        (_) => _m4SignedIn(),
        size: const Size(256, 130),
        states: _hover,
      ),
    )
    ..add(
      acct(
        'signed-in-focus',
        (_) => _m4SignedIn(),
        size: const Size(256, 130),
        states: _focus,
      ),
    )
    ..add(
      acct(
        'signed-in-long-name',
        (_) => _m4SignedIn(
          initial: 'A',
          name: 'Alexandra Konstantinopoulos-Wang',
          handle: '@alexandra.konstantinopoulos',
        ),
        size: const Size(256, 130),
      ),
    )
    ..add(
      acct(
        'menu-open',
        (c) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LgMenuPanel(width: 192, items: _m4AccountMenu()),
            const SizedBox(height: LgSpace.s2),
            LgStateOverride(
              states: const {WidgetState.selected},
              child: _m4SignedIn(),
            ),
          ],
        ),
        size: const Size(256, 250),
      ),
    )
    ..add(
      acct(
        'confirm-sign-out',
        (_) => const LgAccountConfirm(
          title: '退出登录？',
          body: '退出后，地址簿、同组设备和出口目录将不可用。',
          onEscape: _noop,
          actions: [
            LgDialogAction(
              label: '退出登录',
              kind: LgButtonKind.primary,
              isDefault: true,
              onPressed: _noop,
            ),
            LgDialogAction(label: '取消', onPressed: _noop),
          ],
        ),
        size: const Size(256, 270),
      ),
    )
    ..add(
      acct(
        'confirm-sign-out-english',
        (_) => const LgAccountConfirm(
          title: 'Sign out?',
          body:
              'After you sign out, address books, team devices and the exit directory are unavailable.',
          onEscape: _noop,
          actions: [
            LgDialogAction(
              label: 'Sign out',
              kind: LgButtonKind.primary,
              isDefault: true,
              onPressed: _noop,
            ),
            LgDialogAction(label: 'Cancel', onPressed: _noop),
          ],
        ),
        size: const Size(256, 340),
      ),
    );

  // Login dialog ------------------------------------------------------------
  Specimen login(
    String name, {
    LgLoginDialogLabels labels = _m4LoginLabels,
    String user = 'zhangsan',
    String pass = '',
    String? userError,
    String? passError,
    String? loadError,
    bool busy = false,
    double height = 520,
  }) => Specimen(
    'login-dialog',
    name,
    Size(1280, height),
    padding: 0,
    (_) => _dialogStage(
      height: height,
      LgLoginDialog(
        labels: labels,
        usernameController: TextEditingController(text: user),
        passwordController: TextEditingController(text: pass),
        usernameError: userError,
        passwordError: passError,
        loadError: loadError,
        onRetry: loadError == null ? null : _noop,
        busy: busy,
        onSubmit: _noop,
        onCancel: _noop,
      ),
    ),
  );
  list
    ..add(login('default', pass: ''))
    ..add(login('typed', pass: 'password'))
    ..add(login('no-user', user: '', pass: 'password', userError: '请输入用户名'))
    ..add(login('no-password', passError: '请输入密码'))
    ..add(login('server-error', pass: 'password', passError: '用户名或密码错误'))
    ..add(login('busy', pass: 'password', busy: true))
    ..add(login('load-error', loadError: '无法获取登录选项。请检查网络连接。', height: 580))
    ..add(
      login(
        'english-server-error',
        labels: _m4LoginLabelsEn,
        pass: 'password',
        passError: 'Incorrect username or password',
      ),
    )
    ..add(
      login(
        'english-busy',
        labels: _m4LoginLabelsEn,
        pass: 'password',
        busy: true,
      ),
    );

  // Book switcher -----------------------------------------------------------
  Specimen book(
    String name,
    Widget Function(BuildContext) build, {
    Size size = const Size(1072, 120),
    Set<WidgetState> states = const {},
  }) => Specimen('book-switcher', name, size, states: states, build);
  Widget switcher(
    String id, {
    List<LgBook> books = _m4Books,
    bool tools = true,
  }) => LgBookSwitcher(
    books: books,
    selectedId: id,
    onSelect: (_) {},
    searchPlaceholder: books == _m4BooksEn ? 'Search address books' : '搜索地址簿',
    noMatchLabel: books == _m4BooksEn ? 'No address book found' : '未找到匹配的地址簿',
    hint: books == _m4BooksEn
        ? 'Members and permissions of shared address books are set by the administrator'
        : '共享地址簿的成员和权限由管理员设置',
    semanticLabel: books == _m4BooksEn ? 'Switch address book' : '切换地址簿',
    trailing: tools
        ? LgListToolMenu(
            icon: LgIcons.more,
            label: books == _m4BooksEn ? 'More' : '更多',
            items: _m4MoreMenu(),
          )
        : null,
  );
  Widget openPanel(
    String id, {
    String search = '',
    List<LgBook> books = _m4Books,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LgStateOverride(
        states: const {WidgetState.selected},
        child: SizedBox(width: 1040, child: switcher(id, books: books)),
      ),
      const SizedBox(height: LgSpace.s1),
      LgBookPanel(
        books: [
          for (final b in books)
            if (b.name.toLowerCase().contains(search.toLowerCase())) b,
        ],
        selectedId: id,
        onSelect: (_) {},
        searchController: TextEditingController(text: search),
        searchPlaceholder: books == _m4BooksEn
            ? 'Search address books'
            : '搜索地址簿',
        noMatchLabel: books == _m4BooksEn
            ? 'No address book found'
            : '未找到匹配的地址簿',
        hint: books == _m4BooksEn
            ? 'Members and permissions of shared address books are set by the administrator'
            : '共享地址簿的成员和权限由管理员设置',
      ),
    ],
  );
  list
    ..add(
      book('full-control', (_) => SizedBox(width: 1040, child: switcher('me'))),
    )
    ..add(
      book('editable', (_) => SizedBox(width: 1040, child: switcher('home'))),
    )
    ..add(
      book(
        'read-only',
        (_) => SizedBox(width: 1040, child: switcher('friends')),
      ),
    )
    ..add(
      book(
        'hover',
        (_) => SizedBox(width: 1040, child: switcher('home', tools: false)),
        states: _hover,
      ),
    )
    ..add(
      book(
        'focus',
        (_) => SizedBox(width: 1040, child: switcher('home', tools: false)),
        states: _focus,
      ),
    )
    ..add(
      book(
        'english',
        (_) =>
            SizedBox(width: 1040, child: switcher('home', books: _m4BooksEn)),
      ),
    )
    ..add(
      book(
        'long-name',
        (_) => SizedBox(
          width: 1040,
          child: switcher(
            'long',
            books: const [
              LgBook(id: 'me', name: '我的地址簿', detail: '完全控制'),
              LgBook(
                id: 'long',
                name: '家里所有的电脑、服务器、测试机和各个房间里的设备的地址簿',
                detail: '可编辑 · 所有者：Alexandra Konstantinopoulos-Wang',
              ),
            ],
          ),
        ),
      ),
    )
    ..add(book('open', (_) => openPanel('me'), size: const Size(1072, 400)))
    ..add(
      book(
        'open-no-match',
        (_) => openPanel('me', search: 'zzz'),
        size: const Size(1072, 320),
      ),
    )
    ..add(
      book(
        'open-english',
        (_) => openPanel('home', books: _m4BooksEn),
        size: const Size(1072, 440),
      ),
    );

  // Address book page, composed as the mockup ----------------------------------
  list
    ..add(
      Specimen(
        'address-book-page',
        'editable',
        page,
        (c) => SizedBox(width: 1040, child: _m4BookPage(c)),
      ),
    )
    ..add(
      Specimen(
        'address-book-page',
        'tags-on',
        page,
        (c) => SizedBox(
          width: 1040,
          child: _m4BookPage(c, tagsOn: const {'home', 'work'}),
        ),
      ),
    );

  // Tag filter ----------------------------------------------------------------
  Specimen tags(
    String name,
    Widget Function(BuildContext) build, {
    Size size = const Size(1072, 90),
    Set<WidgetState> states = const {},
  }) => Specimen('tag-filter', name, size, states: states, build);
  list
    ..add(
      tags(
        'none-on',
        (c) => SizedBox(
          width: 1040,
          child: LgTagFilterBar(
            items: _m4TagItems(c),
            onToggle: (_) {},
            semanticLabel: '标签筛选',
          ),
        ),
      ),
    )
    ..add(
      tags(
        'two-on',
        (c) => SizedBox(
          width: 1040,
          child: LgTagFilterBar(
            items: _m4TagItems(c, on: const {'home', 'work'}),
            onToggle: (_) {},
            semanticLabel: '标签筛选',
          ),
        ),
      ),
    )
    ..add(
      tags(
        'untagged-on',
        (c) => SizedBox(
          width: 1040,
          child: LgTagFilterBar(
            items: _m4TagItems(c, on: const {'none'}),
            onToggle: (_) {},
            semanticLabel: '标签筛选',
          ),
        ),
      ),
    )
    ..add(
      tags(
        'hover',
        (c) => SizedBox(
          width: 1040,
          child: LgTagFilterBar(
            items: _m4TagItems(c),
            onToggle: (_) {},
            semanticLabel: '标签筛选',
          ),
        ),
        states: _hover,
      ),
    )
    ..add(
      tags(
        'focus',
        (c) => SizedBox(
          width: 1040,
          child: LgTagFilterBar(
            items: _m4TagItems(c, on: const {'home'}),
            onToggle: (_) {},
            semanticLabel: '标签筛选',
          ),
        ),
        states: _focus,
      ),
    )
    ..add(
      tags(
        'overflowing',
        (c) => SizedBox(
          width: 560,
          child: LgTagFilterBar(
            items: _m4TagItems(c, on: const {'home'}, more: true),
            onToggle: (_) {},
            semanticLabel: '标签筛选',
          ),
        ),
        size: const Size(592, 90),
      ),
    )
    ..add(
      tags(
        'chooser',
        (c) => SizedBox(
          width: 420,
          child: LgTagChooser(
            items: _m4TagItems(c, on: const {'home'}, untagged: false),
            onToggle: (_) {},
            semanticLabel: '标签',
          ),
        ),
        size: const Size(452, 90),
      ),
    )
    ..add(
      tags(
        'chooser-busy',
        (c) => SizedBox(
          width: 420,
          child: LgTagChooser(
            items: _m4TagItems(c, on: const {'home'}, untagged: false),
            onToggle: null,
            semanticLabel: '标签',
          ),
        ),
        size: const Size(452, 90),
      ),
    );

  // Address book menus (the existing menu rows) -------------------------------
  list
    ..add(
      Specimen(
        'address-book-menu',
        'more-editable',
        const Size(392, 300),
        (_) => LgMenuPanel(items: _m4MoreMenu()),
      ),
    )
    ..add(
      Specimen(
        'address-book-menu',
        'more-read-only',
        const Size(392, 170),
        (_) => LgMenuPanel(items: _m4MoreMenu(readOnly: true)),
      ),
    )
    ..add(
      Specimen(
        'address-book-menu',
        'device-read-only',
        const Size(392, 600),
        (_) => LgMenuPanel(
          items: [
            LgMenuCheckItem(label: '始终经中继连接', value: false, onChanged: (_) {}),
            const LgMenuItem(label: '创建桌面快捷方式', onPressed: _noop),
            const LgMenuGroup('管理', note: '此地址簿为只读'),
            const LgMenuItem(label: '重命名', onPressed: null),
            const LgMenuItem(label: '加入收藏', onPressed: _noop),
            const LgMenuItem(label: '加入地址簿', onPressed: _noop),
            const LgMenuItem(label: '编辑标签', onPressed: null),
            const LgMenuItem(label: '编辑备注', onPressed: null),
            const LgMenuItem(label: '设置共享密码', onPressed: null),
            const LgMenuItem(label: '清除保存的密码', onPressed: _noop),
            const LgMenuItem(label: '查看所在地址簿', onPressed: _noop),
            const LgMenuGroup('危险操作'),
            const LgMenuItem(label: '从地址簿中删除', danger: true, onPressed: null),
          ],
        ),
      ),
    );

  // People of the team devices ---------------------------------------------------
  Specimen people(
    String name, {
    String? selected,
    String search = '',
    bool english = false,
    Set<WidgetState> states = const {},
    List<LgPerson>? only,
  }) {
    final all =
        only ??
        [
          LgPerson(
            id: 'zhangsan',
            initial: english ? 'Z' : '张',
            name: english ? 'Zhang San' : '张三',
            isMe: true,
          ),
          LgPerson(
            id: 'lisi',
            initial: english ? 'L' : '李',
            name: english ? 'Li Si' : '李四',
          ),
          LgPerson(
            id: 'wangwu',
            initial: english ? 'W' : '王',
            name: english ? 'Wang Wu' : '王五',
          ),
        ];
    return Specimen(
      'people-list',
      name,
      const Size(320, 260),
      states: states,
      (_) => LgPeopleList(
        people: [
          for (final p in all)
            if (p.name.contains(search)) p,
        ],
        selectedId: selected,
        onSelect: (_) {},
        onClear: _noop,
        searchController: TextEditingController(text: search),
        searchPlaceholder: english ? 'Search people' : '搜索人员',
        meLabel: english ? '(me)' : '（我）',
        clearLabel: english ? 'Clear filter' : '取消筛选',
        semanticLabel: english ? 'People' : '人员',
      ),
    );
  }

  list
    ..add(people('nobody-selected'))
    ..add(people('selected', selected: 'lisi'))
    ..add(people('selected-focus', selected: 'lisi', states: _focus))
    ..add(people('hover', states: _hover))
    ..add(people('searched', search: '李'))
    ..add(people('english', selected: 'lisi', english: true))
    ..add(
      people(
        'long-names',
        selected: 'long',
        only: const [
          LgPerson(id: 'me', initial: 'A', name: 'Alexandra', isMe: true),
          LgPerson(
            id: 'long',
            initial: 'K',
            name: 'Konstantinopoulos-Wang Alexandra Maria',
          ),
        ],
      ),
    );
  list.add(
    Specimen(
      'people-list',
      'with-devices',
      page,
      (c) => SizedBox(
        width: 1040,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LgListToolbar(
              tabs: LgCategoryTabs<int>(
                categories: const [
                  LgCategory(0, '最近'),
                  LgCategory(1, '收藏'),
                  LgCategory(2, '局域网'),
                  LgCategory(3, '地址簿'),
                  LgCategory(4, '同组设备'),
                ],
                selected: 4,
                onSelect: (_) {},
              ),
            ),
            const SizedBox(height: LgSpace.s4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LgPeopleList(
                  people: const [
                    LgPerson(
                      id: 'zhangsan',
                      initial: '张',
                      name: '张三',
                      isMe: true,
                    ),
                    LgPerson(id: 'lisi', initial: '李', name: '李四'),
                    LgPerson(id: 'wangwu', initial: '王', name: '王五'),
                  ],
                  selectedId: 'lisi',
                  onSelect: (_) {},
                  onClear: _noop,
                  searchController: TextEditingController(),
                  searchPlaceholder: '搜索人员',
                  meLabel: '（我）',
                  clearLabel: '取消筛选',
                  semanticLabel: '人员',
                ),
                const SizedBox(width: LgSpace.s5),
                Expanded(
                  child: LgDeviceCardGrid(
                    semanticLabel: '李四的设备',
                    children: [
                      for (final n in [2, 4])
                        LgDeviceCard(
                          name: ['', '', '李四的台式机', '', '李四的笔记本'][n],
                          id: _devices[n].id,
                          platform: _devices[n].platform,
                          status: _devices[n].status,
                          statusLabel: _devices[n].statusLabel,
                          userHost: n == 2
                              ? 'lisi@DESKTOP-LISI'
                              : 'lisi@LAPTOP-LISI',
                          onTap: _noop,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  // List states -----------------------------------------------------------------
  Specimen state(
    String name,
    Widget Function(BuildContext) build, {
    int tab = 3,
    Size size = const Size(1072, 370),
  }) => Specimen(
    'list-states',
    name,
    size,
    (c) => SizedBox(
      width: 1040,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _listToolbar(selected: tab, sort: true, refresh: true),
          const SizedBox(height: LgSpace.s4),
          build(c),
        ],
      ),
    ),
  );
  list
    ..add(
      state(
        'sign-in-address-book',
        (_) => const LgEmptyState(
          '登录后可查看地址簿',
          icon: LgIcons.book,
          actionLabel: '登录',
          actionIcon: LgIcons.login,
          onAction: _noop,
        ),
      ),
    )
    ..add(
      state(
        'sign-in-team-devices',
        tab: 4,
        (_) => const LgEmptyState(
          '登录后可查看同组设备',
          icon: LgIcons.users,
          actionLabel: '登录',
          actionIcon: LgIcons.login,
          onAction: _noop,
        ),
      ),
    )
    ..add(
      state(
        'network-error',
        (c) => LgEmptyState(
          '无法连接服务器',
          icon: LgIcons.wifiOff,
          iconColor: LgTokens.of(c).colors.error,
          actionLabel: '重试',
          actionIcon: LgIcons.refresh,
          onAction: _noop,
        ),
      ),
    )
    ..add(
      state(
        'empty-address-book',
        (_) => const LgEmptyState('此地址簿中暂无设备', icon: LgIcons.book),
        size: const Size(1072, 320),
      ),
    )
    ..add(
      state(
        'empty-team-devices',
        tab: 4,
        (_) => const LgEmptyState('暂无同组设备', icon: LgIcons.users),
        size: const Size(1072, 320),
      ),
    )
    ..add(
      state(
        'server-has-no-address-book',
        (_) => const LgEmptyState('当前服务器不提供地址簿。', icon: LgIcons.book),
        size: const Size(1072, 320),
      ),
    )
    ..add(
      state(
        'loading',
        (_) => LgDeviceCardGrid(
          semanticLabel: '正在加载',
          children: [for (var i = 0; i < 6; i++) const LgDeviceCardSkeleton()],
        ),
        size: const Size(1072, 380),
      ),
    )
    ..add(
      state(
        'banner-load-failed',
        (c) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LgBanner(
              tone: LgTone.error,
              slim: true,
              text: '无法加载地址簿。服务器返回：服务暂不可用。',
              actionLabel: '重试',
              actionIcon: LgIcons.refresh,
              onAction: _noop,
              dismissLabel: '关闭',
              onDismiss: _noop,
            ),
            const SizedBox(height: LgSpace.s4),
            LgDeviceCardGrid(
              children: [
                for (final n in [0, 1, 2])
                  LgDeviceCard(
                    name: _devices[n].name,
                    id: _devices[n].id,
                    platform: _devices[n].platform,
                    status: _devices[n].status,
                    statusLabel: _devices[n].statusLabel,
                    userHost: _devices[n].userHost,
                    tags: _tagsOf(c, [n == 2 ? 1 : 0]),
                    favorite: n == 0,
                    favoriteLabel: '已收藏',
                    onTap: _noop,
                  ),
              ],
            ),
          ],
        ),
        size: const Size(1072, 320),
      ),
    )
    ..add(
      state(
        'banner-save-failed',
        (_) => const LgBanner(
          tone: LgTone.error,
          slim: true,
          text: '无法保存地址簿的更改。服务器返回：只读地址簿不能修改。',
          actionLabel: '重试',
          actionIcon: LgIcons.refresh,
          onAction: _noop,
          dismissLabel: '关闭',
          onDismiss: _noop,
        ),
        size: const Size(1072, 180),
      ),
    )
    ..add(
      state(
        'banner-english',
        (_) => const LgBanner(
          tone: LgTone.error,
          slim: true,
          text:
              'Could not load the address book. The server returned: service unavailable.',
          actionLabel: 'Retry',
          actionIcon: LgIcons.refresh,
          onAction: _noop,
          dismissLabel: 'Close',
          onDismiss: _noop,
        ),
        size: const Size(1072, 180),
      ),
    );

  // Notes of devices ------------------------------------------------------------
  list
    ..add(
      Specimen(
        'device-note',
        'card',
        const Size(380, 160),
        (c) => SizedBox(
          width: 340,
          child: LgDeviceCard(
            name: '工作室绘图电脑',
            id: '891 234 567',
            platform: LgPlatform.windows,
            status: LgDeviceStatus.online,
            statusLabel: '在线',
            userHost: 'studio@DESKTOP-STUDIO',
            note: '显卡驱动别升级',
            tags: _tagsOf(c, [1, 2]),
            onTap: _noop,
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'device-note',
        'card-hover',
        const Size(380, 160),
        states: _hover,
        (c) => SizedBox(
          width: 340,
          child: LgDeviceCard(
            name: '工作室绘图电脑',
            id: '891 234 567',
            platform: LgPlatform.windows,
            status: LgDeviceStatus.online,
            statusLabel: '在线',
            userHost: 'studio@DESKTOP-STUDIO',
            note: '显卡驱动别升级',
            tags: _tagsOf(c, [1, 2]),
            onTap: _noop,
            onConnect: _noop,
            connectLabel: '连接',
            onMore: _noop,
            moreLabel: '更多操作',
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'device-note',
        'card-long-note',
        const Size(380, 160),
        (c) => SizedBox(
          width: 340,
          child: LgDeviceCard(
            name: '工作室绘图电脑',
            id: '891 234 567',
            platform: LgPlatform.windows,
            status: LgDeviceStatus.online,
            statusLabel: '在线',
            userHost: 'studio@DESKTOP-STUDIO',
            note: '显卡驱动别升级，系统更新也先别装，等设计组确认过再说',
            tags: _tagsOf(c, [1, 2]),
            onTap: _noop,
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'device-note',
        'table',
        const Size(1072, 330),
        (c) => SizedBox(
          width: 1040,
          child: LgDeviceTable(
            semanticLabel: '地址簿中的设备',
            columns: const [
              LgTableColumn(LgDeviceColumn.status, '状态', sortable: true),
              LgTableColumn(LgDeviceColumn.name, '名称', sortable: true),
              LgTableColumn(LgDeviceColumn.id, 'ID', sortable: true),
              LgTableColumn(LgDeviceColumn.userHost, '用户@主机', sortable: true),
              LgTableColumn(LgDeviceColumn.note, '备注'),
              LgTableColumn(LgDeviceColumn.tags, '标签'),
            ],
            sort: const LgTableSort(LgDeviceColumn.name),
            onSort: (_) {},
            moreColumn: true,
            ascendingLabel: '升序',
            descendingLabel: '降序',
            rows: [
              for (final (i, n) in [0, 1, 2, 7].indexed)
                LgDeviceRow(
                  name: _devices[n].name,
                  id: _devices[n].id,
                  platform: _devices[n].platform,
                  status: _devices[n].status,
                  statusLabel: _devices[n].statusLabel,
                  userHost: _devices[n].userHost,
                  note: n == 7 ? '显卡驱动别升级' : (n == 0 ? '放在阳台的那台' : ''),
                  tags: _tagsOf(c, n == 7 ? [1, 2] : [0]),
                  favorite: i == 0,
                  favoriteLabel: '已收藏',
                  topDivider: i != 0,
                  onTap: _noop,
                  onMore: _noop,
                  moreLabel: '更多操作',
                ),
            ],
          ),
        ),
      ),
    );

  // Add-device dialog -----------------------------------------------------------
  Specimen add(
    String name, {
    LgAddDeviceLabels labels = _m4AddLabels,
    String id = '246 813 579',
    String? idError,
    String? error,
    bool busy = false,
    bool shared = true,
    String note = '',
    Set<String> on = const {'home'},
    String target = '添加到：家里的电脑',
    String hint = '这些内容对此地址簿的其他成员可见',
    double height = 860,
  }) => Specimen(
    'add-device-dialog',
    name,
    Size(1280, height),
    padding: 0,
    (_) => _dialogStage(
      height: height,
      Builder(
        builder: (context) => LgAddDeviceDialog(
          labels: labels,
          target: target,
          idController: TextEditingController(text: id),
          aliasController: TextEditingController(text: '阳台电脑'),
          passwordController: shared
              ? TextEditingController(text: 'password')
              : null,
          passwordHint: shared ? hint : null,
          noteController: TextEditingController(text: note),
          tags: _m4TagItems(context, on: on, untagged: false),
          onToggleTag: (_) {},
          idError: idError,
          error: error,
          busy: busy,
          onSubmit: _noop,
          onCancel: _noop,
        ),
      ),
    ),
  );
  list
    ..add(add('shared-book'))
    ..add(add('personal-book', shared: false, height: 780))
    ..add(add('busy', busy: true))
    ..add(add('duplicate-id', id: '123 456 789', idError: '该 ID 已在此地址簿中'))
    ..add(add('book-full', error: '已达到此地址簿的设备数量上限', height: 920))
    ..add(add('server-error', error: '无法添加设备。服务器返回：服务暂不可用。', height: 920))
    ..add(add('note-typed', note: '放在阳台，晚上会关机', on: const {'home', 'work'}))
    ..add(
      add(
        'english',
        labels: _m4AddLabelsEn,
        target: 'Add to: Home computers',
        hint: 'Other members of this address book can see these',
        error: 'This address book has reached its device limit',
        height: 920,
      ),
    );

  // Colour of a tag -------------------------------------------------------------
  Specimen colorDialog(
    String name, {
    LgTagColorDialogLabels labels = _m4ColorLabels,
    Color initial = const Color(0xFFA65B80),
    bool custom = false,
    bool busy = false,
    String? error,
    double height = 720,
    String tag = '家里',
    String? device = '书房台式机',
  }) => Specimen(
    'tag-color-dialog',
    name,
    Size(1280, height),
    padding: 0,
    (_) => _dialogStage(
      height: height,
      LgTagColorDialog(
        labels: labels,
        tagName: tag,
        previewName: device,
        initialColor: initial,
        startCustom: custom,
        busy: busy,
        error: error,
        onSave: (_) {},
        onCancel: _noop,
      ),
    ),
  );
  list
    ..add(colorDialog('preset-selected', height: 640))
    ..add(
      colorDialog(
        'other-preset',
        initial: const Color(0xFF009184),
        height: 640,
      ),
    )
    ..add(colorDialog('custom', custom: true, initial: const Color(0xFFE0852B)))
    ..add(
      colorDialog(
        'custom-dark-color',
        custom: true,
        initial: const Color(0xFF3A2457),
      ),
    )
    ..add(
      colorDialog(
        'busy',
        busy: true,
        height: 640,
        initial: const Color(0xFF009184),
      ),
    )
    ..add(
      colorDialog(
        'failed',
        initial: const Color(0xFF009184),
        error: '无法修改标签颜色。\n服务器返回：服务暂不可用。',
        height: 700,
      ),
    )
    ..add(
      colorDialog(
        'english',
        labels: _m4ColorLabelsEn,
        custom: true,
        initial: const Color(0xFFE0852B),
        tag: 'Home',
        device: 'Study desktop',
      ),
    );
  // The wheel with a typed value that is not a colour needs typing: it is in
  // the test (test/tag_color_dialog_test.dart) and in the live specimen below.
  list.add(
    Specimen(
      'tag-color-dialog',
      'live',
      const Size(1280, 760),
      padding: 0,
      (_) => _dialogStage(
        height: 760,
        LgTagColorDialog(
          labels: _m4ColorLabels,
          tagName: '家里',
          previewName: '书房台式机',
          initialColor: const Color(0xFFA65B80),
          startCustom: true,
          onSave: (_) {},
          onCancel: _noop,
        ),
      ),
    ),
  );

  // Pickers on their own ---------------------------------------------------------
  list
    ..add(
      Specimen(
        'color-wheel',
        'wheel',
        const Size(240, 200),
        (_) => const LgColorWheel(
          hue: 330,
          saturation: .55,
          value: 1,
          semanticLabel: '色轮',
          semanticValue: '#C4527D',
          onChanged: _ignore2,
        ),
      ),
    )
    ..add(
      Specimen(
        'color-wheel',
        'wheel-dim',
        const Size(240, 200),
        (_) => const LgColorWheel(
          hue: 200,
          saturation: .8,
          value: .55,
          semanticLabel: '色轮',
          onChanged: _ignore2,
        ),
      ),
    )
    ..add(
      Specimen(
        'color-wheel',
        'wheel-focus',
        const Size(240, 200),
        states: _focus,
        (_) => const LgColorWheel(
          hue: 330,
          saturation: .55,
          value: 1,
          semanticLabel: '色轮',
          onChanged: _ignore2,
        ),
      ),
    )
    ..add(
      Specimen(
        'color-wheel',
        'wheel-disabled',
        const Size(240, 200),
        (_) => const LgColorWheel(
          hue: 330,
          saturation: .55,
          value: 1,
          enabled: false,
          semanticLabel: '色轮',
          onChanged: _ignore2,
        ),
      ),
    )
    ..add(
      Specimen(
        'color-wheel',
        'value-bar',
        const Size(320, 80),
        (_) => const SizedBox(
          width: 288,
          child: LgValueBar(
            hue: 330,
            saturation: .55,
            value: .7,
            semanticLabel: '明度',
            onChanged: _ignoreValue,
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'color-wheel',
        'value-bar-focus',
        const Size(320, 80),
        states: _focus,
        (_) => const SizedBox(
          width: 288,
          child: LgValueBar(
            hue: 330,
            saturation: .55,
            value: 0,
            semanticLabel: '明度',
            onChanged: _ignoreValue,
          ),
        ),
      ),
    );

  // Small dialogs built on the shell ------------------------------------------------
  Specimen small(
    String name,
    Widget Function(BuildContext) build, {
    double height = 520,
  }) => Specimen(
    'form-dialog',
    name,
    Size(1280, height),
    padding: 0,
    (c) => _dialogStage(height: height, Builder(builder: build)),
  );
  list
    ..add(
      small(
        'rename-tag',
        (c) => LgFormDialog(
          title: '重命名标签',
          icon: LgIcons.tag,
          width: 400,
          actions: const [
            LgDialogAction(label: '取消', onPressed: _noop),
            LgDialogAction(
              label: '保存',
              kind: LgButtonKind.primary,
              isDefault: true,
              onPressed: _noop,
            ),
          ],
          children: [
            LgFormField(
              label: '标签名称',
              required: true,
              child: LgTextField(
                controller: TextEditingController(text: '家里'),
                semanticLabel: '标签名称',
                autofocus: true,
              ),
            ),
          ],
        ),
        height: 460,
      ),
    )
    ..add(
      small(
        'rename-tag-exists',
        (c) => LgFormDialog(
          title: '重命名标签',
          icon: LgIcons.tag,
          width: 400,
          actions: const [
            LgDialogAction(label: '取消', onPressed: _noop),
            LgDialogAction(
              label: '保存',
              kind: LgButtonKind.primary,
              isDefault: true,
              onPressed: _noop,
            ),
          ],
          children: [
            LgFormField(
              label: '标签名称',
              required: true,
              child: LgTextField(
                controller: TextEditingController(text: '工作'),
                semanticLabel: '标签名称',
                errorText: '已有同名标签',
              ),
            ),
          ],
        ),
        height: 480,
      ),
    )
    ..add(
      small(
        'edit-note',
        (c) => LgFormDialog(
          title: '编辑备注',
          icon: LgIcons.note,
          note: '书房台式机',
          width: 440,
          actions: const [
            LgDialogAction(label: '取消', onPressed: _noop),
            LgDialogAction(
              label: '保存',
              kind: LgButtonKind.primary,
              isDefault: true,
              onPressed: _noop,
            ),
          ],
          children: [
            LgFormField(
              label: '备注',
              counter: '7 / 300',
              child: LgTextArea(
                controller: TextEditingController(text: '显卡驱动别升级'),
                semanticLabel: '备注',
                maxLength: 300,
              ),
            ),
          ],
        ),
        height: 520,
      ),
    )
    ..add(
      small(
        'saving',
        (c) => LgFormDialog(
          title: '编辑备注',
          icon: LgIcons.note,
          note: '书房台式机',
          width: 440,
          actions: const [
            LgDialogAction(label: '取消', onPressed: _noop),
            LgDialogAction(
              label: '正在保存…',
              kind: LgButtonKind.primary,
              busy: true,
              onPressed: _noop,
            ),
          ],
          children: [
            LgFormField(
              label: '备注',
              counter: '7 / 300',
              child: LgTextArea(
                controller: TextEditingController(text: '显卡驱动别升级'),
                semanticLabel: '备注',
                enabled: false,
              ),
            ),
          ],
        ),
        height: 520,
      ),
    );
  return list;
}

void _ignore2(double a, double b) {}
void _ignoreValue(double v) {}
