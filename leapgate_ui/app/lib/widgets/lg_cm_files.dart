// The file record panel of the connection manager (CM): what a visitor's file
// transfer session did on this computer (01 §3.3, 02 §0.4 item 11; `.flog`,
// `.fr` in A-P3.html). Display only: nothing here can be pressed.
//
// The direction is told from this computer's side: "上传到本机" (the visitor
// sends here), "从本机下载" (the visitor takes from here).

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';

/// What one record is about; it picks the icon.
enum LgCmFileAction { toHere, fromHere, newFolder, rename, delete }

LgIcons lgCmFileIcon(LgCmFileAction action) => switch (action) {
  LgCmFileAction.toHere => LgIcons.download,
  LgCmFileAction.fromHere => LgIcons.send,
  LgCmFileAction.newFolder => LgIcons.folder,
  LgCmFileAction.rename => LgIcons.edit,
  LgCmFileAction.delete => LgIcons.trash,
};

enum LgCmFileState { running, done, failed }

/// One record. [progress] (0..1) draws the bar of a running transfer and
/// [resultLabel] is then its percentage; for a finished one [resultLabel] is
/// "已完成" or "失败".
class LgCmFileEntry {
  const LgCmFileEntry({
    required this.action,
    required this.actionLabel,
    required this.name,
    required this.state,
    required this.resultLabel,
    this.size,
    this.progress,
  });

  final LgCmFileAction action;

  /// "上传到本机", "从本机下载", "新建文件夹", "重命名", "删除".
  final String actionLabel;

  /// The file name; a rename reads "旧名 → 新名".
  final String name;

  /// The size as text ("48.6 MB"), when the action has one.
  final String? size;
  final LgCmFileState state;
  final String resultLabel;
  final double? progress;
}

/// The records, newest where the caller puts them, or [emptyText] ("暂无文件
/// 传输记录") with a quiet icon when there are none. Fills the side panel.
class LgCmFileLog extends StatelessWidget {
  const LgCmFileLog({
    super.key,
    required this.entries,
    required this.emptyText,
  });

  final List<LgCmFileEntry> entries;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    if (entries.isEmpty) {
      return Semantics(
        container: true,
        label: emptyText,
        child: ExcludeSemantics(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(LgRadius.r12),
                  ),
                  child: LgIcon(LgIcons.files, size: 24, color: c.text2),
                ),
                const SizedBox(height: LgSpace.s3),
                Text(emptyText, style: t.text.copyWith(color: c.text2)),
              ],
            ),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: LgSpace.s4,
        vertical: LgSpace.s2,
      ),
      children: [
        for (final (i, e) in entries.indexed)
          DecoratedBox(
            decoration: BoxDecoration(
              border: i == 0 ? null : Border(top: BorderSide(color: c.border)),
            ),
            child: _FileRow(entry: e),
          ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.entry});

  final LgCmFileEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final (resultColor, resultIcon) = switch (entry.state) {
      LgCmFileState.running => (c.text, null),
      LgCmFileState.done => (c.online, LgIcons.checkCircle),
      LgCmFileState.failed => (c.error, LgIcons.err),
    };
    final detail = [
      entry.name,
      entry.actionLabel,
      ?entry.size,
      entry.resultLabel,
    ].join(', ');
    return Semantics(
      container: true,
      label: detail,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: LgSpace.s2),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(LgRadius.r10),
                  ),
                  child: LgIcon(
                    lgCmFileIcon(entry.action),
                    size: 20,
                    color: c.text2,
                  ),
                ),
                const SizedBox(width: LgSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.copyWith(
                          color: c.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            entry.actionLabel,
                            maxLines: 1,
                            style: t.textS.copyWith(
                              color: c.text2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (entry.size != null) ...[
                            const SizedBox(width: LgSpace.s2),
                            Flexible(
                              child: Text(
                                entry.size!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.textS.copyWith(color: c.text2),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (entry.progress != null)
                        Padding(
                          padding: const EdgeInsets.only(top: LgSpace.s2),
                          child: _Progress(entry.progress!),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: LgSpace.s3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (resultIcon != null) ...[
                      LgIcon(resultIcon, size: 16, color: resultColor),
                      const SizedBox(width: LgSpace.s1),
                    ],
                    Text(
                      entry.resultLabel,
                      maxLines: 1,
                      style: t.textS.copyWith(
                        color: resultColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 4 px bar of a running transfer (`.sl`, without the knob).
class _Progress extends StatelessWidget {
  const _Progress(this.value);

  final double value;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: c.track,
        borderRadius: BorderRadius.circular(2),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(2),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
