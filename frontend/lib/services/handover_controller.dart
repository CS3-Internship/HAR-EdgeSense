import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import 'package:edge_sense/config/network_config.dart';
import 'package:edge_sense/services/fuzzy_handover.dart';
import 'package:edge_sense/services/wifi_rssi.dart';

enum HandoverState { stable, degraded, switching, switched }

class HandoverStatus {
  final HandoverState state;
  final double urgency;
  final String signalLabel;
  final String currentServer;
  final String message;

  const HandoverStatus({
    required this.state,
    required this.urgency,
    required this.signalLabel,
    required this.currentServer,
    required this.message,
  });

  factory HandoverStatus.initial() => const HandoverStatus(
        state: HandoverState.stable,
        urgency: 0,
        signalLabel: 'Good',
        currentServer: '',
        message: 'Connecting…',
      );
}

class _ProbeResult {
  final bool ok;
  final double? latencyMs;
  const _ProbeResult({required this.ok, this.latencyMs});
}

/// Watches the current edge-server connection (Wi-Fi RSSI + request latency)
/// through a fuzzy-logic urgency score, and migrates the session to a new edge
/// server when the device roams to a different network gateway.
///
/// Two things are migrated on handoff:
///   1. In-RAM state (unconsumed sliding-window buffer, step count, last
///      prediction) via the small JSON /session/{id}/snapshot + /restore API,
///      needed so inference doesn't have to "cold start" on the new server.
///   2. The session's actual SQLite file — the same file docker-compose.yml
///      mounts at /app/data/sessions/session_<id>.db — downloaded whole from
///      the old server and uploaded whole to the new one via
///      /session/{id}/database, so persisted history moves byte-for-byte
///      instead of being replayed row by row through the JSON API.
///
/// Because the OS — not this app — decides which Wi-Fi AP the phone associates
/// with, this controller can't "choose" to switch servers proactively. What the
/// fuzzy score buys us instead:
///   1. Predictive caching — while urgency is elevated, it opportunistically
///      pre-fetches both of the above from the current server, so they're
///      already in hand if the connection dies before a roam is detected.
///   2. A degraded-signal warning when the connection is poor but no alternate
///      edge server is visible on the current network (nothing to hand off to).
///   3. Smoothing (EMA) so a single noisy reading doesn't flap the UI status.
class HandoverController {
  final String Function() sessionIdProvider;
  final void Function(String newServerUrl) onServerChanged;

  final ValueNotifier<HandoverStatus> status = ValueNotifier(HandoverStatus.initial());

  static const _tickInterval = Duration(seconds: 4);
  static const _handoffCooldown = Duration(seconds: 15);
  static const _cacheInterval = Duration(seconds: 5);
  static const _predictiveCacheThreshold = 55.0;
  static const _degradedThreshold = 70.0;

  Timer? _timer;
  int _consecutiveFailures = 0;
  double _smoothedUrgency = 0;
  Map<String, dynamic>? _cachedSnapshot;
  Uint8List? _cachedDbBytes;
  DateTime? _lastCacheTime;
  DateTime? _lastHandoffTime;
  bool _handoffInProgress = false;

  HandoverController({required this.sessionIdProvider, required this.onServerChanged});

  void start() {
    if (kIsWeb) return;
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) => _tick());
    _tick();
  }

  void dispose() {
    _timer?.cancel();
  }

  Future<void> _tick() async {
    if (_handoffInProgress || serverBaseUrl.isEmpty) return;
    final sessionId = sessionIdProvider();

    final rssi = await WifiRssi.getRssi();
    final probe = await _probe(serverBaseUrl);
    _consecutiveFailures = probe.ok ? 0 : _consecutiveFailures + 1;

    final fuzzy = FuzzyHandoverEngine.evaluate(
      rssi: rssi,
      latencyMs: probe.latencyMs,
      consecutiveFailures: _consecutiveFailures,
      timedOut: !probe.ok,
    );
    _smoothedUrgency = _smoothedUrgency == 0 ? fuzzy.urgency : (0.4 * fuzzy.urgency + 0.6 * _smoothedUrgency);

    if (_smoothedUrgency >= _predictiveCacheThreshold && probe.ok && sessionId.isNotEmpty) {
      final since = _lastCacheTime;
      if (since == null || DateTime.now().difference(since) > _cacheInterval) {
        final snap = await _fetchSnapshot(serverBaseUrl, sessionId);
        final dbBytes = await _downloadDatabase(serverBaseUrl, sessionId);
        if (snap != null) _cachedSnapshot = snap;
        if (dbBytes != null) _cachedDbBytes = dbBytes;
        if (snap != null || dbBytes != null) _lastCacheTime = DateTime.now();
      }
    }

    String? gateway;
    try {
      gateway = await NetworkInfo().getWifiGatewayIP();
    } catch (e) {
      debugPrint('HandoverController: gateway lookup failed: $e');
    }
    final candidateServer = (gateway != null && gateway.isNotEmpty) ? 'http://$gateway:5000' : null;

    final cooldownElapsed = _lastHandoffTime == null || DateTime.now().difference(_lastHandoffTime!) > _handoffCooldown;

    if (candidateServer != null && candidateServer != serverBaseUrl && cooldownElapsed && sessionId.isNotEmpty) {
      _handoffInProgress = true;
      status.value = HandoverStatus(
        state: HandoverState.switching,
        urgency: _smoothedUrgency,
        signalLabel: fuzzy.label,
        currentServer: serverBaseUrl,
        message: 'New network detected — migrating session to $candidateServer…',
      );
      await _performHandoff(
        sessionId: sessionId,
        oldServer: serverBaseUrl,
        newServer: candidateServer,
        liveProbeOk: probe.ok,
      );
      _handoffInProgress = false;
      return;
    }

    status.value = HandoverStatus(
      state: _smoothedUrgency >= _degradedThreshold ? HandoverState.degraded : HandoverState.stable,
      urgency: _smoothedUrgency,
      signalLabel: fuzzy.label,
      currentServer: serverBaseUrl,
      message: _smoothedUrgency >= _degradedThreshold
          ? 'Signal weak — no alternate edge server detected on this network.'
          : 'Connected to edge server.',
    );
  }

  Future<_ProbeResult> _probe(String server) async {
    final sw = Stopwatch()..start();
    try {
      final res = await http.get(Uri.parse('$server/ping')).timeout(const Duration(seconds: 2));
      sw.stop();
      return _ProbeResult(ok: res.statusCode == 200, latencyMs: sw.elapsedMilliseconds.toDouble());
    } catch (e) {
      sw.stop();
      return const _ProbeResult(ok: false, latencyMs: null);
    }
  }

  Future<Map<String, dynamic>?> _fetchSnapshot(String server, String sessionId) async {
    try {
      final res = await http.get(Uri.parse('$server/session/$sessionId/snapshot')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('HandoverController: snapshot fetch from $server failed: $e');
    }
    return null;
  }

  Future<Uint8List?> _downloadDatabase(String server, String sessionId) async {
    try {
      final res = await http.get(Uri.parse('$server/session/$sessionId/database')).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (e) {
      debugPrint('HandoverController: database download from $server failed: $e');
    }
    return null;
  }

  Future<bool> _uploadDatabase(String server, String sessionId, Uint8List bytes) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$server/session/$sessionId/database'))
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'session_$sessionId.db'));
      final streamedRes = await request.send().timeout(const Duration(seconds: 10));
      return streamedRes.statusCode == 200;
    } catch (e) {
      debugPrint('HandoverController: database upload to $server failed: $e');
      return false;
    }
  }

  Future<bool> _restoreSnapshot(String server, String sessionId, Map<String, dynamic> snapshot) async {
    try {
      final res = await http
          .post(
            Uri.parse('$server/session/$sessionId/restore'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'step_count': snapshot['step_count'] ?? 0,
              'buffer': snapshot['buffer'] ?? [],
              'last_prediction': snapshot['last_prediction'] ?? {},
            }),
          )
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('HandoverController: restore on $server failed: $e');
      return false;
    }
  }

  /// Deletes the session's data on the server it's leaving, once it's confirmed
  /// to have landed on the new one. Best-effort: if the old server is already
  /// unreachable (the common case — that's usually *why* the phone roamed), there's
  /// nothing to clean up there anyway, so failures here are just logged.
  Future<void> _purgeOldServer(String server, String sessionId) async {
    try {
      await http.delete(Uri.parse('$server/session/$sessionId')).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('HandoverController: purge of old server $server failed (likely already unreachable): $e');
    }
  }

  Future<void> _performHandoff({
    required String sessionId,
    required String oldServer,
    required String newServer,
    required bool liveProbeOk,
  }) async {
    Map<String, dynamic>? snapshot;
    Uint8List? dbBytes;
    if (liveProbeOk) {
      snapshot = await _fetchSnapshot(oldServer, sessionId);
      dbBytes = await _downloadDatabase(oldServer, sessionId);
    }
    snapshot ??= _cachedSnapshot;
    dbBytes ??= _cachedDbBytes;

    bool candidateReady = false;
    for (var attempt = 0; attempt < 4; attempt++) {
      final probe = await _probe(newServer);
      if (probe.ok) {
        candidateReady = true;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 750));
    }

    bool restoredOnNewServer = false;
    if (candidateReady && snapshot != null) {
      restoredOnNewServer = await _restoreSnapshot(newServer, sessionId, snapshot);
    }

    bool databaseMigrated = false;
    if (candidateReady && dbBytes != null) {
      databaseMigrated = await _uploadDatabase(newServer, sessionId, dbBytes);
    }

    // Only wipe the old server's copy once something has actually landed on the
    // new one — never delete the only copy of the data on a failed handoff.
    if (candidateReady && (restoredOnNewServer || databaseMigrated)) {
      await _purgeOldServer(oldServer, sessionId);
    }

    _cachedSnapshot = null;
    _cachedDbBytes = null;
    _lastCacheTime = null;
    _lastHandoffTime = DateTime.now();
    _smoothedUrgency = 0;
    _consecutiveFailures = 0;

    serverBaseUrl = newServer;
    onServerChanged(newServer);

    status.value = HandoverStatus(
      state: HandoverState.switched,
      urgency: 0,
      signalLabel: 'Good',
      currentServer: newServer,
      message: candidateReady
          ? 'Switched to edge server at $newServer.'
          : 'Moved to $newServer, waiting for it to come online…',
    );
  }
}
