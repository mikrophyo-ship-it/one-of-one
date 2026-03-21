import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    required this.settings,
    required this.onSave,
    super.key,
  });

  final PlatformSettingsSnapshot? settings;
  final Future<void> Function(
    int platformFeeBps,
    int defaultRoyaltyBps,
    Map<String, dynamic> marketplaceRules,
    Map<String, dynamic> brandSettings,
  )
  onSave;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _platformFeeController;
  late final TextEditingController _defaultRoyaltyController;
  late final TextEditingController _marketplaceRulesController;
  late final TextEditingController _brandSettingsController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _platformFeeController = TextEditingController();
    _defaultRoyaltyController = TextEditingController();
    _marketplaceRulesController = TextEditingController();
    _brandSettingsController = TextEditingController();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _syncControllers();
    }
  }

  @override
  void dispose() {
    _platformFeeController.dispose();
    _defaultRoyaltyController.dispose();
    _marketplaceRulesController.dispose();
    _brandSettingsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('Settings', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 10),
        Text(
          'Persist platform fee, default royalty, marketplace policy copy, and brand JSON without shipping those decisions into client code.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: _platformFeeController,
                          decoration: const InputDecoration(
                            labelText: 'Platform fee (bps)',
                          ),
                          validator: _validateBps,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _defaultRoyaltyController,
                          decoration: const InputDecoration(
                            labelText: 'Default royalty (bps)',
                          ),
                          validator: _validateBps,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _marketplaceRulesController,
                    minLines: 6,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Marketplace rules JSON',
                    ),
                    validator: _validateJson,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _brandSettingsController,
                    minLines: 6,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Brand settings JSON',
                    ),
                    validator: _validateJson,
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save settings'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String? _validateBps(String? value) {
    final String input = value?.trim() ?? '';
    if (input.isEmpty) {
      return 'Basis points are required.';
    }
    final int? parsed = int.tryParse(input);
    if (parsed == null || parsed < 0 || parsed > 5000) {
      return 'Enter a value between 0 and 5000.';
    }
    return null;
  }

  String? _validateJson(String? value) {
    final String input = value?.trim() ?? '';
    if (input.isEmpty) {
      return 'JSON is required.';
    }
    try {
      final dynamic parsed = jsonDecode(input);
      if (parsed is! Map<String, dynamic>) {
        return 'Provide a JSON object.';
      }
    } catch (_) {
      return 'Enter valid JSON.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
    });
    final Map<String, dynamic> marketplaceRules =
        jsonDecode(_marketplaceRulesController.text.trim())
            as Map<String, dynamic>;
    final Map<String, dynamic> brandSettings =
        jsonDecode(_brandSettingsController.text.trim())
            as Map<String, dynamic>;
    await widget.onSave(
      int.parse(_platformFeeController.text.trim()),
      int.parse(_defaultRoyaltyController.text.trim()),
      marketplaceRules,
      brandSettings,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
    });
  }

  void _syncControllers() {
    final PlatformSettingsSnapshot settings =
        widget.settings ??
        const PlatformSettingsSnapshot(
          platformFeeBps: 1000,
          defaultRoyaltyBps: 1200,
          marketplaceRules: <String, dynamic>{},
          brandSettings: <String, dynamic>{},
        );
    _platformFeeController.text = '${settings.platformFeeBps}';
    _defaultRoyaltyController.text = '${settings.defaultRoyaltyBps}';
    _marketplaceRulesController.text = const JsonEncoder.withIndent(
      '  ',
    ).convert(settings.marketplaceRules);
    _brandSettingsController.text = const JsonEncoder.withIndent(
      '  ',
    ).convert(settings.brandSettings);
  }
}
