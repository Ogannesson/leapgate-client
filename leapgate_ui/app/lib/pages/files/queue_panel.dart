import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/leapgate/file_transfer/jobs.dart';

/// The transfer queue at the bottom of the file transfer view (02 §2.2 block H): the summary
/// line, the rows, collapsing and dragging its height. Coder B's; the file view (coder C)
/// places it below the panes and gives it the full width (`LEAPGATE.md` §10.15).
// TODO(M7a shell): coder B builds the panel.
class FileQueuePanel extends StatelessWidget {
  const FileQueuePanel({super.key, required this.jobs});

  final FileJobs jobs;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
