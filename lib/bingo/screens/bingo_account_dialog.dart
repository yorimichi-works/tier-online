import 'package:flutter/material.dart';

import '../../services/account_auth_service.dart';
import '../l10n/bingo_localizations.dart';
import '../services/bingo_state.dart';
import '../theme/bingo_theme.dart';

/// Sign in / sign up with the account shared with Tier Online. Returns true
/// when the user ends up signed in (and verified, for password accounts).
Future<bool> showBingoAccountDialog(
  BuildContext context,
  BingoState state, {
  String? reason,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _AccountDialog(state: state, reason: reason),
        ),
      ),
    ) ??
    false;

String authErrorMessage(BingoLocalizations strings, AuthResultStatus status) =>
    strings.t(switch (status) {
      AuthResultStatus.emailInUse => 'authErrorEmailInUse',
      AuthResultStatus.weakPassword => 'authErrorWeakPassword',
      AuthResultStatus.invalidEmail => 'authErrorInvalidEmail',
      AuthResultStatus.wrongPassword => 'authErrorWrongPassword',
      AuthResultStatus.userNotFound => 'authErrorUserNotFound',
      AuthResultStatus.credentialInUse => 'authErrorCredentialInUse',
      AuthResultStatus.googleAccountConflict ||
      AuthResultStatus.generic ||
      AuthResultStatus.success => 'authErrorGeneric',
    });

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.state, this.reason});

  final BingoState state;
  final String? reason;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignUp = true;
  bool _submitting = false;
  bool _verifying = false;

  BingoState get state => widget.state;
  AccountAuthService? get account => state.account;

  @override
  void initState() {
    super.initState();
    _verifying = state.needsEmailVerification;
    // A redirect Google sign-in may have ended in an account conflict.
    if (state.pendingGoogleAccountEmail != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolveGoogleConflict();
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _finish() {
    if (state.needsEmailVerification) {
      setState(() => _verifying = true);
      return;
    }
    _snack(context.bingo.t('signedIn'));
    Navigator.of(context).pop(true);
  }

  Future<void> _submit() async {
    final account = this.account;
    if (account == null || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (!_isSignUp && !await _confirmSwitch()) return;
    setState(() => _submitting = true);
    final email = _email.text.trim();
    final result = _isSignUp
        ? await account.signUpWithEmail(email, _password.text)
        : await account.signInWithEmail(email, _password.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      _finish();
    } else {
      _snack(authErrorMessage(context.bingo, result.status));
    }
  }

  /// Signing in to an existing account (instead of upgrading the guest)
  /// switches the uid, so guest-made boards stop showing on this device.
  Future<bool> _confirmSwitch() async {
    final strings = context.bingo;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: Text(strings.t('switchAccountWarning')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(strings.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(strings.t('signIn')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _google() async {
    final account = this.account;
    if (account == null) return;
    setState(() => _submitting = true);
    final result = await account.signInWithGoogle();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      _finish();
    } else if (result.status == AuthResultStatus.googleAccountConflict) {
      await _resolveGoogleConflict();
    } else {
      _snack(authErrorMessage(context.bingo, result.status));
    }
  }

  Future<void> _resolveGoogleConflict() async {
    final account = this.account;
    final email = account?.pendingGoogleAccountEmail;
    if (account == null || email == null) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordPrompt(
        title: context.bingo.t('googleConflictTitle'),
        body: context.bingo.format('googleConflictBody', {'email': email}),
        action: context.bingo.t('signIn'),
      ),
    );
    if (password == null) {
      account.clearPendingGoogleCredential();
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = true);
    final result = await account.linkPendingGoogleCredential(password);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      _finish();
    } else {
      _snack(authErrorMessage(context.bingo, result.status));
    }
  }

  Future<void> _resetPassword() async {
    final account = this.account;
    final email = _email.text.trim();
    if (account == null || email.isEmpty) {
      _snack(context.bingo.t('authErrorInvalidEmail'));
      return;
    }
    final result = await account.sendPasswordReset(email);
    if (!mounted) return;
    _snack(
      result.isSuccess
          ? context.bingo.t('passwordResetSent')
          : authErrorMessage(context.bingo, result.status),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    if (account == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: 12),
            Text(strings.t('authOffline'), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.t('close')),
            ),
          ],
        ),
      );
    }
    if (_verifying) {
      return EmailVerificationPanel(
        state: state,
        onVerified: () {
          _snack(strings.t('emailVerified'));
          Navigator.of(context).pop(true);
        },
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.t('signInOrRegister'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              widget.reason ?? strings.t('accountGuestBody'),
              style: const TextStyle(color: BingoColors.inkMuted, height: 1.45),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(strings.t('createAccount')),
                ),
                ButtonSegment(value: false, label: Text(strings.t('signIn'))),
              ],
              selected: {_isSignUp},
              onSelectionChanged: (value) =>
                  setState(() => _isSignUp = value.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('account-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: strings.t('email')),
              validator: (value) {
                final text = value?.trim() ?? '';
                return text.isEmpty || !text.contains('@')
                    ? strings.t('authErrorInvalidEmail')
                    : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('account-password'),
              controller: _password,
              obscureText: true,
              autofillHints: [
                _isSignUp ? AutofillHints.newPassword : AutofillHints.password,
              ],
              decoration: InputDecoration(labelText: strings.t('password')),
              validator: (value) => (value?.length ?? 0) < 6
                  ? strings.t('authErrorWeakPassword')
                  : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (!_isSignUp)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _submitting ? null : _resetPassword,
                  child: Text(strings.t('forgotPassword')),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('account-submit'),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(strings.t(_isSignUp ? 'createAccount' : 'signIn')),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    strings.t('orDivider'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: BingoColors.inkMuted,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const ValueKey('account-google'),
              onPressed: _submitting ? null : _google,
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: Text(strings.t('signInWithGoogle')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown until a password account verifies its address. Also used on the
/// settings screen.
class EmailVerificationPanel extends StatefulWidget {
  const EmailVerificationPanel({
    super.key,
    required this.state,
    required this.onVerified,
    this.padding = const EdgeInsets.all(24),
  });

  final BingoState state;
  final VoidCallback onVerified;
  final EdgeInsetsGeometry padding;

  @override
  State<EmailVerificationPanel> createState() => _EmailVerificationPanelState();
}

class _EmailVerificationPanelState extends State<EmailVerificationPanel> {
  bool _busy = false;
  DateTime? _lastResend;

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _resend() async {
    final last = _lastResend;
    // Firebase throttles verification mails; keep a short cooldown.
    if (last != null && DateTime.now().difference(last).inSeconds < 45) {
      _snack(context.bingo.t('emailResent'));
      return;
    }
    setState(() => _busy = true);
    final sent = await widget.state.account?.sendVerificationEmail() ?? false;
    if (!mounted) return;
    setState(() => _busy = false);
    if (sent) _lastResend = DateTime.now();
    _snack(context.bingo.t(sent ? 'emailResent' : 'authErrorGeneric'));
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    final verified =
        await widget.state.account?.refreshEmailVerified() ?? false;
    if (!mounted) return;
    setState(() => _busy = false);
    if (verified) {
      widget.onVerified();
    } else {
      _snack(context.bingo.t('notVerifiedYet'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.bingo;
    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.mark_email_unread_outlined,
            size: 36,
            color: BingoColors.primary,
          ),
          const SizedBox(height: 10),
          Text(
            strings.t('verifyEmailTitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            strings.format('verifyEmailBody', {
              'email': widget.state.accountEmail ?? '',
            }),
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.5),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('verify-check'),
            onPressed: _busy ? null : _check,
            child: Text(strings.t('checkVerified')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _resend,
            child: Text(strings.t('resendEmail')),
          ),
        ],
      ),
    );
  }
}

/// Password prompt that owns its controller (it must outlive the closing
/// animation of the dialog).
class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt({
    required this.title,
    required this.body,
    required this.action,
  });

  final String title;
  final String body;
  final String action;

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isNotEmpty) Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.body),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('password-prompt'),
          controller: _controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: context.bingo.t('password')),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.bingo.t('cancel')),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}

/// Asks for the password of a password account before deleting it.
Future<String?> showPasswordPrompt(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PasswordPrompt(title: title, body: body, action: action),
);
