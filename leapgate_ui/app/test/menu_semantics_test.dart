// What an open menu sends to the engine (docs/新界面/无障碍语义树为空排查.md, the
// appendix's probe). The Windows bridge drops every node that root 0 cannot
// reach, and reads a node without the button flag as plain text.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_menu_items.dart';

import 'helpers.dart';

/// Each update the framework sent: node id → children in traversal order.
final _updates = <Map<int, List<int>>>[];

class _ProbeBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() => _Spy();
}

class _Spy extends Fake implements ui.SemanticsUpdateBuilder {
  _Spy() {
    _updates.add({});
  }

  final _builder = ui.SemanticsUpdateBuilder();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final a = invocation.namedArguments;
      _updates.last[a[#id] as int] =
          (a[#childrenInTraversalOrder] as Int32List).toList();
      return Function.apply(_builder.updateNode, const [], a);
    }
    return super.noSuchMethod(invocation);
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => _builder.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() => _builder.build();
}

/// The engine's tree, update by update.
final _tree = <int, List<int>>{};

/// The nodes sent since the last call that root 0 cannot reach.
List<int> _orphans() {
  final out = <int>[];
  for (final u in _updates.where((u) => u.isNotEmpty)) {
    final next = {..._tree, ...u};
    final seen = <int>{};
    void walk(int id) {
      if (seen.add(id)) next[id]?.forEach(walk);
    }

    if (next.containsKey(0)) walk(0);
    out.addAll(u.keys.where((id) => !seen.contains(id)));
    _tree
      ..clear()
      ..addAll({for (final id in seen) id: next[id]!});
  }
  _updates.clear();
  return out;
}

const _long = '这是一个很长很长的菜单项名称放不下时省略并在悬停时显示全文这是一个很长很长的菜单项名称';

List<Widget> _items() => [
  const LgMenuGroup('显示'),
  LgMenuItem(label: '适应窗口', checked: true, onPressed: () {}),
  LgMenuItem(label: _long, onPressed: () {}),
  LgMenuItem(label: '经中继连接', description: '比直连慢', onPressed: () {}),
  const LgMenuItem(label: '交换控制方向', onPressed: null, disabledNote: '对方不允许'),
  LgMenuSwitchItem(label: '同步剪贴板', value: true, onChanged: (_) {}),
  LgSubmenu(
    label: '显示器',
    items: [LgMenuItem(label: '显示器 2', onPressed: () {})],
  ),
];

void main() {
  _ProbeBinding();

  setUp(() {
    _updates.clear();
    _tree.clear();
  });

  testWidgets('an open dropdown and submenu send no unreachable node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpLg(
      tester,
      LgMenuAnchor(
        items: _items(),
        builder: (context, c) =>
            LgIconButton(icon: LgIcons.more, label: '更多', onPressed: c.open),
      ),
    );
    expect(_orphans(), isEmpty);
    await tester.tap(find.bySemanticsLabel('更多'));
    await tester.pumpAndSettle();
    expect(find.text('适应窗口'), findsOneWidget);
    expect(_orphans(), isEmpty);
    await tester.tap(find.text('显示器'));
    await tester.pumpAndSettle();
    expect(find.text('显示器 2'), findsOneWidget);
    expect(_orphans(), isEmpty);
    handle.dispose();
  });

  testWidgets('a context menu and a menu at a point send no unreachable node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpLg(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LgContextMenuRegion(
            items: _items(),
            child: const SizedBox(width: 200, height: 60, child: Text('区域')),
          ),
          Builder(
            builder: (context) => LgButton(
              label: '标签',
              onPressed: () => showLgMenuAt(
                context,
                globalPosition: const Offset(100, 100),
                items: _items(),
              ),
            ),
          ),
        ],
      ),
    );
    expect(_orphans(), isEmpty);
    await tester.tap(find.text('区域'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('适应窗口'), findsOneWidget);
    expect(_orphans(), isEmpty);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.tap(find.text('标签'));
    await tester.pumpAndSettle();
    expect(find.text('适应窗口'), findsOneWidget);
    expect(_orphans(), isEmpty);
    handle.dispose();
  });

  testWidgets('menu rows are buttons a screen reader can press', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpLg(
      tester,
      LgMenuAnchor(
        items: _items(),
        builder: (context, c) => LgButton(label: '视图', onPressed: c.open),
      ),
    );
    await tester.tap(find.text('视图'));
    await tester.pumpAndSettle();
    for (final label in ['适应窗口', _long, '经中继连接\n比直连慢', '显示器']) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
        reason: label,
      );
    }
    expect(
      tester.getSemantics(find.bySemanticsLabel('交换控制方向')),
      isSemantics(isButton: true, isEnabled: false, hasTapAction: false),
    );
    handle.dispose();
  });
}
