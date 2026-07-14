class EdgeHotspot {
  final String ssid;
  final String password;

  /// This edge server's address, e.g. "http://192.168.43.1:5000". Explicit and
  /// user-provided rather than derived from the Wi-Fi gateway IP, because phone
  /// personal hotspots commonly all default to the same gateway address
  /// (e.g. 192.168.43.1) regardless of which phone is hosting them — deriving
  /// the URL from gateway IP would make two different edge servers resolve to
  /// the identical address.
  final String serverUrl;

  const EdgeHotspot({required this.ssid, required this.password, required this.serverUrl});

  Map<String, dynamic> toJson() => {'ssid': ssid, 'password': password, 'serverUrl': serverUrl};

  factory EdgeHotspot.fromJson(Map<String, dynamic> json) => EdgeHotspot(
        ssid: json['ssid'] as String,
        password: json['password'] as String? ?? '',
        serverUrl: json['serverUrl'] as String? ?? '',
      );
}
