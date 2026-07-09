import 'package:flutter/material.dart';
import 'package:edge_sense/screens/system_information_screen.dart';

class SystemInfoButton extends StatelessWidget {
  final String sessionId;
  final ValueNotifier<AppState> appStateNotifier;

  const SystemInfoButton({
    super.key,
    required this.sessionId,
    required this.appStateNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      icon: const Icon(Icons.info_outline),
      tooltip: "System Information",
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SystemInformationScreen(
              sessionId: sessionId,
              appStateNotifier: appStateNotifier,
            ),
          ),
        );
      },
    );
  }
}
