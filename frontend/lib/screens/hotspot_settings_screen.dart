import 'package:flutter/material.dart';

import 'package:edge_sense/constants/theme.dart';
import 'package:edge_sense/models/edge_hotspot.dart';
import 'package:edge_sense/services/hotspot_manager.dart';

/// Lets the user register every edge-server hotspot's Wi-Fi name/password, so
/// Android can roam between them automatically instead of getting stuck on
/// whichever one it joined first.
class HotspotSettingsScreen extends StatefulWidget {
  const HotspotSettingsScreen({super.key});

  @override
  State<HotspotSettingsScreen> createState() => _HotspotSettingsScreenState();
}

class _HotspotSettingsScreenState extends State<HotspotSettingsScreen> {
  List<EdgeHotspot> _hotspots = [];
  bool _loading = true;
  bool _applying = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hotspots = await HotspotManager.load();
    if (!mounted) return;
    setState(() {
      _hotspots = hotspots;
      _loading = false;
    });
  }

  Future<void> _apply() async {
    setState(() {
      _applying = true;
      _statusMessage = null;
    });
    final message = await HotspotManager.saveAndApply(_hotspots);
    if (!mounted) return;
    setState(() {
      _applying = false;
      _statusMessage = message;
    });
  }

  Future<void> _addOrEdit({EdgeHotspot? existing, int? index}) async {
    final result = await showDialog<EdgeHotspot>(
      context: context,
      builder: (_) => _HotspotDialog(existing: existing),
    );
    if (result == null) return;
    setState(() {
      if (index != null) {
        _hotspots[index] = result;
      } else {
        _hotspots.add(result);
      }
    });
    _apply();
  }

  void _delete(int index) {
    setState(() => _hotspots.removeAt(index));
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.colorBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.colorBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.colorTextDark),
        title: const Text(
          'Edge Server Networks',
          style: TextStyle(color: AppTheme.colorTextDark, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Register the Wi-Fi name and password of every edge-server hotspot. '
                    'Android will then roam between them automatically as you move, instead '
                    'of staying stuck on whichever one it joined first.',
                    style: AppTheme.styleSubtitle,
                  ),
                  const SizedBox(height: 20),
                  if (_hotspots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No hotspots added yet.', style: AppTheme.styleLabel),
                    )
                  else
                    ..._hotspots.asMap().entries.map((entry) {
                      final index = entry.key;
                      final hotspot = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.colorCardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.colorBorder, width: 1),
                        ),
                        child: ListTile(
                          title: Text(
                            hotspot.ssid,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.colorTextDark),
                          ),
                          subtitle: Text(
                            hotspot.password.isEmpty ? 'Open network' : '•' * hotspot.password.length,
                            style: AppTheme.styleLabel,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20, color: AppTheme.colorTextGrey),
                                onPressed: () => _addOrEdit(existing: hotspot, index: index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.colorError),
                                onPressed: () => _delete(index),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _addOrEdit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Hotspot'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.colorPrimary,
                      side: const BorderSide(color: AppTheme.colorPrimary, width: 1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_applying || _hotspots.isEmpty) ? null : _apply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.colorPrimary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _applying
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Apply to Wi-Fi'),
                    ),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_statusMessage!, style: AppTheme.styleLabel),
                  ],
                ],
              ),
            ),
    );
  }
}

class _HotspotDialog extends StatefulWidget {
  final EdgeHotspot? existing;

  const _HotspotDialog({this.existing});

  @override
  State<_HotspotDialog> createState() => _HotspotDialogState();
}

class _HotspotDialogState extends State<_HotspotDialog> {
  late final TextEditingController _ssidController =
      TextEditingController(text: widget.existing?.ssid ?? '');
  late final TextEditingController _passwordController =
      TextEditingController(text: widget.existing?.password ?? '');
  String? _error;

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) {
      setState(() => _error = 'Wi-Fi name is required');
      return;
    }
    Navigator.pop(context, EdgeHotspot(ssid: ssid, password: _passwordController.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Hotspot' : 'Edit Hotspot'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ssidController,
            decoration: InputDecoration(labelText: 'Wi-Fi Name (SSID)', errorText: _error),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: 'Password (blank if open network)'),
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
