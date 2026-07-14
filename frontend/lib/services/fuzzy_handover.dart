/// Fuzzy-logic engine that scores how urgently the app should hand its session
/// off to a different edge server, based on Wi-Fi signal strength (RSSI) and
/// request latency. This is a zero-order Sugeno-style fuzzy inference system:
/// inputs are fuzzified into linguistic levels, rules are combined with MIN
/// (fuzzy AND), and the crisp "urgency" output is the weighted average of each
/// rule's singleton consequent.
///
/// Urgency is a score from 0 (rock solid, stay put) to 100 (about to drop,
/// switch now if a candidate is available).
class FuzzyResult {
  final double urgency; // 0-100
  final bool rssiAvailable;

  const FuzzyResult({required this.urgency, required this.rssiAvailable});

  /// A quick qualitative label for display in the UI.
  String get label {
    if (urgency >= 70) return 'Poor';
    if (urgency >= 40) return 'Fair';
    return 'Good';
  }
}

class FuzzyHandoverEngine {
  // Singleton urgency outputs for [rssiLevel][latencyLevel], rssi levels =
  // {poor, fair, good}, latency levels = {fast, medium, slow}.
  static const List<List<double>> _ruleTable = [
    [70, 85, 100], // rssi: poor
    [30, 55, 80], // rssi: fair
    [5, 25, 55], // rssi: good
  ];

  // Latency-only singleton outputs, used when RSSI isn't available (e.g. iOS).
  static const List<double> _latencyOnlyTable = [10, 50, 95]; // fast, medium, slow

  /// Membership of [rssi] (dBm) in {poor, fair, good}. Sums to <= 1 for any input.
  /// The outer sets (poor/good) use an unbounded plateau on their open side so
  /// signal readings beyond the modeled range (e.g. -105 dBm, or a rare +0 dBm
  /// misreport) still saturate at full membership instead of falling to zero.
  static List<double> _fuzzifyRssi(int rssi) {
    final poor = _trapezoid(rssi.toDouble(), double.negativeInfinity, double.negativeInfinity, -85, -65);
    final fair = _triangular(rssi.toDouble(), -85, -70, -55);
    final good = _trapezoid(rssi.toDouble(), -70, -55, double.infinity, double.infinity);
    return [poor, fair, good];
  }

  /// Membership of [latencyMs] in {fast, medium, slow}.
  static List<double> _fuzzifyLatency(double latencyMs) {
    final fast = _trapezoid(latencyMs, 0, 0, 150, 400);
    final medium = _triangular(latencyMs, 150, 500, 1000);
    final slow = _trapezoid(latencyMs, 500, 1000, double.infinity, double.infinity);
    return [fast, medium, slow];
  }

  static double _triangular(double x, double a, double b, double c) {
    if (x <= a || x >= c) return 0.0;
    if (x == b) return 1.0;
    if (x < b) return (x - a) / (b - a);
    return (c - x) / (c - b);
  }

  static double _trapezoid(double x, double a, double b, double c, double d) {
    // Plateau is checked before the "outside" bounds so degenerate flat edges
    // (e.g. a == b, meaning the set is already saturated at its floor) still
    // report full membership instead of being caught by the outside check.
    if (x >= b && x <= c) return 1.0;
    if (x <= a || x >= d) return 0.0;
    if (x < b) return (x - a) / (b - a);
    return (d - x) / (d - c);
  }

  /// Evaluates handover urgency.
  ///
  /// [rssi] is the current Wi-Fi RSSI in dBm, or null if unavailable.
  /// [latencyMs] is the most recent request round-trip time. Pass a large
  /// value (or null with [timedOut] true) to represent a failed/timed-out probe.
  /// [consecutiveFailures] hard-overrides urgency to 100 once a small streak
  /// is reached, since sustained failures mean the link is already broken.
  static FuzzyResult evaluate({
    int? rssi,
    double? latencyMs,
    int consecutiveFailures = 0,
    bool timedOut = false,
  }) {
    if (consecutiveFailures >= 3) {
      return FuzzyResult(urgency: 100, rssiAvailable: rssi != null);
    }

    final effectiveLatency = timedOut ? 2000.0 : (latencyMs ?? 2000.0);
    final latencyMemberships = _fuzzifyLatency(effectiveLatency);

    if (rssi == null) {
      double weighted = 0, weightSum = 0;
      for (var i = 0; i < 3; i++) {
        final w = latencyMemberships[i];
        weighted += w * _latencyOnlyTable[i];
        weightSum += w;
      }
      final urgency = weightSum > 0 ? weighted / weightSum : 50.0;
      return FuzzyResult(urgency: urgency.clamp(0, 100).toDouble(), rssiAvailable: false);
    }

    final rssiMemberships = _fuzzifyRssi(rssi);
    double weighted = 0, weightSum = 0;
    for (var r = 0; r < 3; r++) {
      for (var l = 0; l < 3; l++) {
        final w = rssiMemberships[r] < latencyMemberships[l] ? rssiMemberships[r] : latencyMemberships[l];
        if (w <= 0) continue;
        weighted += w * _ruleTable[r][l];
        weightSum += w;
      }
    }
    final urgency = weightSum > 0 ? weighted / weightSum : 50.0;
    return FuzzyResult(urgency: urgency.clamp(0, 100).toDouble(), rssiAvailable: true);
  }
}
