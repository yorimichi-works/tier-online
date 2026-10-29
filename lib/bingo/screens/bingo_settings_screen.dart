import 'package:flutter/material.dart';

import '../../services/account_auth_service.dart';
import '../l10n/bingo_localizations.dart';
import '../services/bingo_state.dart';
import '../theme/bingo_theme.dart';
import '../widgets/bingo_widgets.dart';
import 'bingo_account_dialog.dart';

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

  void _snack(String key) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.bingo.t(key))));

  Future<void> _signOut() async {
    await widget.state.signOut();
    if (mounted) _snack('signedOut');
  }

  Future<void> _deleteAccount() async {
    final strings = context.bingo;
    final state = widget.state;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.t('deleteAccount')),
        content: Text(strings.t('deleteAccountConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.t('deleteAccount')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    String? password;
    if (state.account?.accountUsesPassword ?? false) {
      password = await showPasswordPrompt(
        context,
        title: strings.t('reauthTitle'),
        body: state.accountEmail ?? '',
        action: strings.t('deleteAccount'),
      );
      if (password == null || !mounted) return;
    }
    final status = await state.deleteAccount(password: password);
    if (!mounted) return;
    switch (status) {
      case AccountDeletionStatus.success:
        _snack('deleteAccountDone');
      case AccountDeletionStatus.wrongPassword:
        _snack('authErrorWrongPassword');
      case AccountDeletionStatus.cancelled:
        break;
      case AccountDeletionStatus.failed:
        _snack('actionFailed');
    }
  }

  Widget _accountSection(BingoLocalizations strings) {
    final state = widget.state;
    if (state.needsEmailVerification) {
      return EmailVerificationPanel(
        state: state,
        padding: EdgeInsets.zero,
        onVerified: () => _snack('emailVerified'),
      );
    }
    final registered = state.isRegistered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: registered
                  ? BingoColors.primary
                  : BingoColors.surfaceStrong,
              foregroundColor: registered ? Colors.white : BingoColors.inkMuted,
              child: Icon(
                registered ? Icons.person_rounded : Icons.person_outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                registered
                    ? strings.format('accountSignedIn', {
                        'email': state.accountEmail ?? '',
                      })
                    : strings.t('accountGuest'),
                key: const ValueKey('account-status'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        if (!registered) ...[
          const SizedBox(height: 8),
          Text(
            strings.t('accountGuestBody'),
            style: const TextStyle(color: BingoColors.inkMuted, height: 1.45),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!registered)
              FilledButton.icon(
                key: const ValueKey('settings-sign-in'),
                onPressed: () => showBingoAccountDialog(context, state),
                icon: const Icon(Icons.login_rounded),
                label: Text(strings.t('signInOrRegister')),
              )
            else ...[
              OutlinedButton.icon(
                key: const ValueKey('settings-sign-out'),
                onPressed: _signOut,
                icon: const Icon(Icons.logout_rounded),
                label: Text(strings.t('signOut')),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _deleteAccount,
                child: Text(strings.t('deleteAccount')),
              ),
            ],
          ],
        ),
      ],
    );
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
              card([label('account'), _accountSection(strings)]),
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
