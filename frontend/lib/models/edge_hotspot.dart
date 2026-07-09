class EdgeHotspot {
  final String ssid;
  final String password;

  const EdgeHotspot({required this.ssid, required this.password});

  Map<String, dynamic> toJson() => {'ssid': ssid, 'password': password};

  factory EdgeHotspot.fromJson(Map<String, dynamic> json) => EdgeHotspot(
        ssid: json['ssid'] as String,
        password: json['password'] as String? ?? '',
      );
}
