import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/common_widgets.dart';
import '../services/app_state.dart';
import 'account_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.appState,
    this.scrollController,
  });
  final AppState appState;
  final ScrollController? scrollController;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: scrollController,
    child: ContentFrame(
      maxWidth: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.t('settings'),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 20),
          if (appState.authEnabled) ...[
            Card(
              child: ListTile(
                leading: Icon(
                  appState.isAnonymous
                      ? Icons.person_outline_rounded
                      : Icons.verified_user_rounded,
                ),
                title: Text(
                  appState.isAnonymous
                      ? context.l10n.t('notSignedIn')
                      : '${context.l10n.t('signedInAs')} ${appState.userEmail}',
                ),
                trailing: appState.isAnonymous
                    ? FilledButton(
                        onPressed: () => showAccountSheet(context, appState),
                        child: Text(context.l10n.t('createAccount')),
                      )
                    : TextButton(
                        onPressed: appState.signOut,
                        child: Text(context.l10n.t('signOut')),
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Column(
              children: [
                _ResponsiveSettingPicker<AppLocale>(
                  icon: Icons.language_rounded,
                  title: Text(context.l10n.t('language')),
                  value: appState.locale,
                  items: [
                    for (final locale in AppLocale.values)
                      DropdownMenuItem(
                        value: locale,
                        child: Text(locale.nativeName),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null || value == appState.locale) return;
                    appState.setLocale(value);
                    Navigator.of(
                      context,
                    ).pushReplacementNamed('/${value.code}/');
                  },
                ),
                const Divider(height: 1),
                _ResponsiveSettingPicker<String>(
                  icon: Icons.public_rounded,
                  title: Text(context.l10n.t('region')),
                  value: appState.region,
                  items: [
                    DropdownMenuItem(
                      value: 'JP',
                      child: Text(context.l10n.t('japan')),
                    ),
                    DropdownMenuItem(
                      value: 'KR',
                      child: Text(context.l10n.t('korea')),
                    ),
                    DropdownMenuItem(
                      value: 'GLOBAL',
                      child: Text(context.l10n.t('globalOther')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) appState.setRegion(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.palette_outlined),
                          const SizedBox(width: 12),
                          Text(
                            context.l10n.t('displayTheme'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      _ThemeModeSelector(
                        value: appState.themeMode,
                        onChanged: appState.setThemeMode,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.animation_rounded),
                  title: Text(context.l10n.t('animations')),
                  subtitle: Text(context.l10n.t('animationsDescription')),
                  value: appState.animationsEnabled,
                  onChanged: appState.setAnimationsEnabled,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    appState.cloudEnabled
                        ? Icons.cloud_done_outlined
                        : Icons.storage_outlined,
                  ),
                  title: Text(
                    appState.cloudEnabled
                        ? context.l10n.t('cloudSync')
                        : context.l10n.t('localStorage'),
                  ),
                  subtitle: Text(
                    appState.cloudEnabled
                        ? appState.cloudError == null
                              ? context.l10n.t('syncedAnonymous')
                              : context.l10n.t('syncRetry')
                        : context.l10n.t('savedLocally'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(context.l10n.t('appName')),
                  subtitle: const Text('Prototype 0.1.0'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                appState.cloudEnabled
                    ? context.l10n.t('anonymousDescription')
                    : context.l10n.t('localBuildDescription'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ResponsiveSettingPicker<T> extends StatelessWidget {
  const _ResponsiveSettingPicker({
    required this.icon,
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final Widget title;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final picker = DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
      );
      if (constraints.maxWidth < 420) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 16),
                  Expanded(child: title),
                ],
              ),
              const SizedBox(height: 4),
              Padding(padding: const EdgeInsets.only(left: 40), child: picker),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 16),
            Expanded(child: title),
            const SizedBox(width: 16),
            SizedBox(width: 220, child: picker),
          ],
        ),
      );
    },
  );
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [
      (ThemeMode.dark, Icons.dark_mode_outlined, context.l10n.t('dark')),
      (ThemeMode.light, Icons.light_mode_outlined, context.l10n.t('light')),
      (
        ThemeMode.system,
        Icons.settings_suggest_outlined,
        context.l10n.t('system'),
      ),
    ];
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('theme-mode-selector'),
      height: 64,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var index = 0; index < options.length; index++) ...[
            if (index > 0)
              VerticalDivider(width: 1, thickness: 1, color: colors.outline),
            Expanded(
              child: _ThemeModeOption(
                mode: options[index].$1,
                icon: options[index].$2,
                label: options[index].$3,
                selected: value == options[index].$1,
                onTap: () => onChanged(options[index].$1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  const _ThemeModeOption({
    required this.mode,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        child: InkWell(
          key: ValueKey('theme-mode-${mode.name}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: selected
                              ? colors.onPrimaryContainer
                              : colors.onSurface,
                          fontWeight: selected
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
