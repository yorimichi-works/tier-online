import 'package:flutter/material.dart';

import '../l10n/bingo_localizations.dart';
import '../services/bingo_state.dart';
import '../theme/bingo_theme.dart';
import '../widgets/bingo_widgets.dart';

class BingoSettingsScreen extends StatefulWidget {
  const BingoSettingsScreen({super.key, required this.state});

  final BingoState state;

  @override
  State<BingoSettingsScreen> createState() => _BingoSettingsScreenState();
}

class _BingoSettingsScreenState extends State<BingoSettingsScreen> {
  late final _name = TextEditingController(text: widget.state.displayName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await widget.state.setDisplayName(_name.text);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.bingo.t('saved'))));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    final state = widget.state;
    Widget card(List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: BingoColors.outline),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    Widget label(String key) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        strings.t(key),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
    return ListView(
      padding: const EdgeInsets.only(top: 20, bottom: 40),
      children: [
        BingoFrame(
          maxWidth: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.t('settingsTitle'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              card([
                label('displayName'),
                TextField(
                  key: const ValueKey('display-name'),
                  controller: _name,
                  maxLength: 24,
                  onSubmitted: (_) => _saveName(),
                  decoration: InputDecoration(
                    hintText: strings.t('guest'),
                    helperText: strings.t('displayNameHint'),
                    suffixIcon: IconButton(
                      tooltip: strings.t('save'),
                      onPressed: _saveName,
                      icon: const Icon(Icons.check_rounded),
                    ),
                  ),
                ),
              ]),
              card([
                label('language'),
                DropdownButtonFormField<AppLocale>(
                  isExpanded: true,
                  key: const ValueKey('language-select'),
                  initialValue: state.locale,
                  items: [
                    for (final locale in AppLocale.values)
                      DropdownMenuItem(
                        value: locale,
                        child: Text(locale.nativeName),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) state.setLocale(value);
                  },
                ),
                const SizedBox(height: 16),
                label('region'),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: state.region,
                  items: [
                    for (final region in SupportedRegion.values)
                      DropdownMenuItem(
                        value: region.code,
                        child: Text(strings.regionName(region.code)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) state.setRegion(value);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  strings.t('regionHelp'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: BingoColors.inkMuted,
                  ),
                ),
              ]),
              card([
                Row(
                  children: [
                    Icon(
                      state.cloudEnabled
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      color: state.cloudEnabled
                          ? const Color(0xFF1E8E4E)
                          : BingoColors.inkMuted,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      strings.t(
                        state.cloudEnabled ? 'syncOnline' : 'syncOffline',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ]),
              card([
                label('aboutTitle'),
                Text(
                  strings.t('aboutBody'),
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 8),
                Text(
                  strings.t('appleNotice'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: BingoColors.inkMuted,
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}
