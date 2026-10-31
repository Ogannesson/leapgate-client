import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

/// One point of the latency line.
typedef LatencyPoint = ({DateTime at, int ms});

/// The end-to-end round trip of one session for the connection details (01 §4.2): the lowest,
/// average and highest since the session started, and a point every 2 s over the last 60 s.
/// It keeps counting across reconnects (`LEAPGATE.md` §10.9). The values are the delay Rust
/// reports with the quality status (about once a second).
class LatencyStats extends ChangeNotifier {
  static const window = Duration(seconds: 60);
  static const step = Duration(seconds: 2);

  final _points = <LatencyPoint>[];
  int? _current;
  int? _min;
  int? _max;
  var _sum = 0;
  var _count = 0;

  /// The latest round trip in ms; null before the first.
  int? get current => _current;
  int? get min => _min;
  int? get max => _max;
  double? get average => _count == 0 ? null : _sum / _count;

  /// The points of the last [window], oldest first.
  List<LatencyPoint> get points {
    final from = clock.now().subtract(window);
    return _points.where((p) => !p.at.isBefore(from)).toList();
  }

  /// Upstream's `update_quality_status` event; only the ones that carry a delay count.
  void onQualityStatus(Map<String, dynamic> evt) {
    final ms = int.tryParse('${evt['delay'] ?? ''}');
    if (ms != null) add(ms);
  }

  void add(int ms) {
    final now = clock.now();
    _current = ms;
    _min = _min == null || ms < _min! ? ms : _min;
    _max = _max == null || ms > _max! ? ms : _max;
    _sum += ms;
    _count++;
    if (_points.isEmpty || now.difference(_points.last.at) >= step) {
      _points.add((at: now, ms: ms));
      final from = now.subtract(window);
      _points.removeWhere((p) => p.at.isBefore(from));
    }
    notifyListeners();
  }
}
