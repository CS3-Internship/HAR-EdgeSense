import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import 'package:edge_sense/config/network_config.dart';
import 'package:edge_sense/models/edge_hotspot.dart';
import 'package:edge_sense/services/fuzzy_handover.dart';
import 'package:edge_sense/services/hotspot_manager.dart';
import 'package:edge_sense/services/wifi_connector.dart';
import 'package:edge_sense/services/wifi_rssi.dart';

enum HandoverState { stable, degraded, switching, switched }

class HandoverStatus {
  final HandoverState state;
  final double urgency;
  final String signalLabel;
  final String currentServer;
  final String previousServer;
  final String message;

  const HandoverStatus({
    required this.state,
    required this.urgency,
    required this.signalLabel,
    required this.currentServer,
    required this.previousServer,
    required this.message,
  });

  factory HandoverStatus.initial() => const HandoverStatus(
        state: HandoverState.stable,
        urgency: 0,
        signalLabel: 'Good',
        currentServer: '',
        previousServer: '',
        message: 'Connecting…',
      );
}

class _ProbeResult {
  final bool ok;
  final double? latencyMs;
  const _ProbeResult({required this.ok, this.latencyMs});
}

/// Watches the current edge-server connection (Wi-Fi RSSI + request latency)
/// through a fuzzy-logic urgency score, and migrates the session to a
/// different edge server registered in [HotspotManager] when appropriate.
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
/// Migration triggers two ways:
///   - **Passive**: the current Wi-Fi network (however it came to change — a
///     manual switch, or Android roaming on its own) already resolves, via
///     [HotspotManager.findBySsid], to a different registered edge server
///     than the one currently in use.
///   - **Active**: once the fuzzy urgency score is elevated, the controller
///     scans for other registered hotspots in range and, if one is found,
///     actively force-connects to it via [WifiConnector] rather than waiting
///     for Android to roam on its own — which it largely won't do while the
///     current network is still functioning, even if weak.
///
/// Other fuzzy-score uses:
///   - Predictive caching — while urgency is elevated, it opportunistically
///     pre-fetches both migration payloads from the current server, so
///     they're already in hand if the connection dies before a switch happens.
///   - A degraded-signal warning when nothing better is found nearby.
///   - Smoothing (EMA) so a single noisy reading doesn't flap the UI status.
class HandoverController {
  final String Function() sessionIdProvider;
  final void Function(String newServerUrl) onServerChanged;

  final ValueNotifier<HandoverStatus> status = ValueNotifier(HandoverStatus.initial());

  static const _tickInterval = Duration(seconds: 4);
  static const _handoffCooldown = Duration(seconds: 15);
  static const _cacheInterval = Duration(seconds: 5);
  static const _hotspotRefreshInterval = Duration(seconds: 30);
  static const _scanInterval = Duration(seconds: 20);
  static const _predictiveCacheThreshold = 55.0;
  static const _scanUrgencyThreshold = 60.0;
  static const _degradedThreshold = 70.0;

  Timer? _timer;
  int _consecutiveFailures = 0;
  double _smoothedUrgency = 0;
  Map<String, dynamic>? _cachedSnapshot;
  Uint8List? _cachedDbBytes;
  DateTime? _lastCacheTime;
  DateTime? _lastHandoffTime;
  bool _handoffInProgress = false;

  List<EdgeHotspot> _hotspots = [];
  DateTime? _lastHotspotRefresh;
  DateTime? _lastScanTime;

  // The server address left behind by the most recent migration (automatic or
  // manual). Kept purely for visibility/debugging — e.g. showing "Previous: X /
  // Current: Y" in a test UI — the actual migration decision always compares
  // against a freshly-resolved current network, not this held-onto value.
  String? _previousServerUrl;
  String? get previousServerUrl => _previousServerUrl;
  String? get currentServerUrl => serverBaseUrl.isEmpty ? null : serverBaseUrl;

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

  /// Reactively checks whatever edge server the phone is actually connected to
  /// *right now* (fresh SSID/gateway resolution, not the smoothed/cooldown-gated
  /// automatic path) and migrates the session to it immediately if that differs
  /// from the server the app currently thinks it's using — without waiting for
  /// the next tick or for the fuzzy urgency score to rise. For testing the
  /// migration pipeline on demand, independent of Wi-Fi-switch detection.
  Future<String> migrateNow() async {
    if (serverBaseUrl.isEmpty) return 'No edge server configured yet.';
    final sessionId = sessionIdProvider();
    if (sessionId.isEmpty) return 'No active session — start the service first.';
    if (_handoffInProgress) return 'A migration is already in progress.';

    if (_lastHotspotRefresh == null || DateTime.now().difference(_lastHotspotRefresh!) > _hotspotRefreshInterval) {
      _hotspots = await HotspotManager.load();
      _lastHotspotRefresh = DateTime.now();
    }

    final resolvedServer = await _resolveServerUrlForCurrentNetwork();
    if (resolvedServer == null) {
      return 'Could not determine an edge server for the current network.';
    }
    if (resolvedServer == serverBaseUrl) {
      return 'Already on $resolvedServer — nothing to migrate.';
    }

    final oldServer = serverBaseUrl;
    final probe = await _probe(oldServer);
    await _handoff(
      sessionId: sessionId,
      oldServer: oldServer,
      newServer: resolvedServer,
      liveProbeOk: probe.ok,
      fuzzyLabel: status.value.signalLabel,
      switchingMessage: 'Manual migration requested — moving session from $oldServer to $resolvedServer…',
      forceConnectHotspot: null,
    );
    return 'Migration to $resolvedServer requested.';
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

    if (_lastHotspotRefresh == null || DateTime.now().difference(_lastHotspotRefresh!) > _hotspotRefreshInterval) {
      _hotspots = await HotspotManager.load();
      _lastHotspotRefresh = DateTime.now();
    }

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

    final cooldownElapsed = _lastHandoffTime == null || DateTime.now().difference(_lastHandoffTime!) > _handoffCooldown;

    // Passive path: has the current network already resolved to a different,
    // known edge server (e.g. the user manually switched Wi-Fi, or Android
    // roamed within a same-SSID mesh on its own)?
    if (cooldownElapsed && sessionId.isNotEmpty) {
      final resolvedServer = await _resolveServerUrlForCurrentNetwork();
      if (resolvedServer != null && resolvedServer != serverBaseUrl) {
        await _handoff(
          sessionId: sessionId,
          oldServer: serverBaseUrl,
          newServer: resolvedServer,
          liveProbeOk: probe.ok,
          fuzzyLabel: fuzzy.label,
          switchingMessage: 'Network change detected — migrating session to $resolvedServer…',
          forceConnectHotspot: null,
        );
        return;
      }
    }

    // Active path: the current connection is degrading — proactively scan for
    // a better registered hotspot and force-connect to it, rather than waiting
    // for Android to roam there on its own.
    final scanDue = _lastScanTime == null || DateTime.now().difference(_lastScanTime!) > _scanInterval;
    if (_smoothedUrgency >= _scanUrgencyThreshold && cooldownElapsed && scanDue && _hotspots.isNotEmpty && sessionId.isNotEmpty) {
      _lastScanTime = DateTime.now();
      final target = await _findBetterHotspot();
      if (target != null) {
        await _handoff(
          sessionId: sessionId,
          oldServer: serverBaseUrl,
          newServer: target.serverUrl,
          liveProbeOk: probe.ok,
          fuzzyLabel: fuzzy.label,
          switchingMessage: 'Signal degrading — switching to ${target.ssid}…',
          forceConnectHotspot: target,
        );
        return;
      }
    }

    status.value = HandoverStatus(
      state: _smoothedUrgency >= _degradedThreshold ? HandoverState.degraded : HandoverState.stable,
      urgency: _smoothedUrgency,
      signalLabel: fuzzy.label,
      currentServer: serverBaseUrl,
      previousServer: _previousServerUrl ?? '',
      message: _smoothedUrgency >= _degradedThreshold
          ? 'Signal weak — searching for a better edge server…'
          : 'Connected to edge server.',
    );
  }

  /// Resolves the edge server address for whatever Wi-Fi network is currently
  /// active, preferring the registered hotspot list (keyed by SSID, since
  /// phone hotspots commonly share the same gateway IP) and falling back to
  /// the legacy gateway-IP guess for unregistered/single-server deployments.
  Future<String?> _resolveServerUrlForCurrentNetwork() async {
    String? ssid;
    try {
      ssid = await NetworkInfo().getWifiName();
    } catch (e) {
      debugPrint('HandoverController: SSID lookup failed: $e');
    }

    final match = HotspotManager.findBySsid(_hotspots, ssid);
    if (match != null) return match.serverUrl;

    try {
      final gateway = await NetworkInfo().getWifiGatewayIP();
      if (gateway != null && gateway.isNotEmpty) return 'http://$gateway:5000';
    } catch (e) {
      debugPrint('HandoverController: gateway lookup failed: $e');
    }
    return null;
  }

  /// Scans for visible Wi-Fi networks and returns the strongest registered
  /// hotspot found that isn't the one currently in use, or null if none.
  Future<EdgeHotspot?> _findBetterHotspot() async {
    final results = await WifiConnector.scan();
    if (results.isEmpty) return null;

    EdgeHotspot? best;
    int? bestRssi;
    for (final r in results) {
      final match = HotspotManager.findBySsid(_hotspots, r.ssid);
      if (match == null || match.serverUrl == serverBaseUrl) continue;
      if (best == null || r.rssi > (bestRssi ?? -999)) {
        best = match;
        bestRssi = r.rssi;
      }
    }
    return best;
  }

  Future<void> _handoff({
    required String sessionId,
    required String oldServer,
    required String newServer,
    required bool liveProbeOk,
    required String fuzzyLabel,
    required String switchingMessage,
    required EdgeHotspot? forceConnectHotspot,
  }) async {
    _handoffInProgress = true;
    status.value = HandoverStatus(
      state: HandoverState.switching,
      urgency: _smoothedUrgency,
      signalLabel: fuzzyLabel,
      currentServer: oldServer,
      previousServer: _previousServerUrl ?? '',
      message: switchingMessage,
    );
    await _migrate(
      sessionId: sessionId,
      oldServer: oldServer,
      newServer: newServer,
      liveProbeOk: liveProbeOk,
      forceConnectHotspot: forceConnectHotspot,
    );
    _handoffInProgress = false;
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

  Future<void> _migrate({
    required String sessionId,
    required String oldServer,
    required String newServer,
    required bool liveProbeOk,
    required EdgeHotspot? forceConnectHotspot,
  }) async {
    Map<String, dynamic>? snapshot;
    Uint8List? dbBytes;
    if (liveProbeOk) {
      snapshot = await _fetchSnapshot(oldServer, sessionId);
      dbBytes = await _downloadDatabase(oldServer, sessionId);
    }
    snapshot ??= _cachedSnapshot;
    dbBytes ??= _cachedDbBytes;

    if (forceConnectHotspot != null) {
      await WifiConnector.connectTo(forceConnectHotspot.ssid, forceConnectHotspot.password);
    }

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

    _previousServerUrl = oldServer;
    serverBaseUrl = newServer;
    onServerChanged(newServer);

    status.value = HandoverStatus(
      state: HandoverState.switched,
      urgency: 0,
      signalLabel: 'Good',
      currentServer: newServer,
      previousServer: oldServer,
      message: candidateReady
          ? 'Switched to edge server at $newServer.'
          : 'Moved to $newServer, waiting for it to come online…',
    );
  }
}
