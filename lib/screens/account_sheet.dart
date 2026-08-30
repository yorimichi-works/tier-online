import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_state.dart';
import 'email_verification_pending_screen.dart';

Future<bool> showAccountSheet(BuildContext context, AppState appState) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _AccountSheetBody(appState: appState),
          ),
        ),
      ) ??
      false;
}

class _AccountSheetBody extends StatefulWidget {
  const _AccountSheetBody({required this.appState});
  final AppState appState;

  @override
  State<_AccountSheetBody> createState() => _AccountSheetBodyState();
}

class _AccountSheetBodyState extends State<_AccountSheetBody> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignUp = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // リダイレクト方式のGoogleログイン完了後、アカウント競合が検出済みの
    // 状態でこのシートが開かれた場合は、通常のログインフォームではなく
    // 統合ダイアログを直接表示する。
    if (widget.appState.pendingGoogleAccountEmail != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolveGoogleAccountConflict();
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _authErrorMessage(AuthResultStatus status) => switch (status) {
    AuthResultStatus.emailInUse => context.l10n.t('authErrorEmailInUse'),
    AuthResultStatus.weakPassword => context.l10n.t('authErrorWeakPassword'),
    AuthResultStatus.invalidEmail => context.l10n.t('authErrorInvalidEmail'),
    AuthResultStatus.wrongPassword => context.l10n.t('authErrorWrongPassword'),
    AuthResultStatus.userNotFound => context.l10n.t('authErrorUserNotFound'),
    AuthResultStatus.credentialInUse => context.l10n.t(
      'authErrorCredentialInUse',
    ),
    AuthResultStatus.googleAccountConflict => context.l10n.t(
      'authErrorGeneric',
    ),
    AuthResultStatus.generic ||
    AuthResultStatus.success => context.l10n.t('authErrorGeneric'),
  };

  Future<void> _finishAuthentication() async {
    if (widget.appState.needsEmailVerification) {
      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) =>
              EmailVerificationPendingScreen(appState: widget.appState),
        ),
      );
      if (!mounted || verified != true) return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_isSignUp) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(context.l10n.t('switchAccountWarning')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.t('signIn')),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    setState(() => _submitting = true);
    final email = _email.text.trim();
    final password = _password.text;
    final result = _isSignUp
        ? await widget.appState.signUpWithEmail(email, password)
        : await widget.appState.signInWithEmail(email, password);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      await _finishAuthentication();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_authErrorMessage(result.status))));
  }

  Future<void> _submitGoogle() async {
    setState(() => _submitting = true);
    final result = await widget.appState.signInWithGoogle();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      await _finishAuthentication();
      return;
    }
    if (result.status == AuthResultStatus.googleAccountConflict) {
      await _resolveGoogleAccountConflict();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_authErrorMessage(result.status))));
  }

  Future<void> _resolveGoogleAccountConflict() async {
    final email = widget.appState.pendingGoogleAccountEmail;
    if (email == null) return;
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('googleAccountConflictTitle')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.format('googleAccountConflictBody', {
                  'email': email,
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.l10n.t('password'),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? context.l10n.t('authErrorWrongPassword')
                    : null,
                onFieldSubmitted: (value) {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.of(dialogContext).pop(value);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.appState.clearPendingGoogleCredential();
              Navigator.of(dialogContext).pop();
            },
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(passwordController.text);
              }
            },
            child: Text(context.l10n.t('signIn')),
          ),
        ],
      ),
    );
    passwordController.dispose();
    if (password == null || !mounted) return;
    setState(() => _submitting = true);
    final result = await widget.appState.linkPendingGoogleCredential(password);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      await _finishAuthentication();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_authErrorMessage(result.status))));
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    final result = await widget.appState.sendPasswordReset(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess
              ? context.l10n.t('passwordResetSent')
              : _authErrorMessage(result.status),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text(context.l10n.t('createAccount')),
              ),
              ButtonSegment(
                value: false,
                label: Text(context.l10n.t('signIn')),
              ),
            ],
            selected: {_isSignUp},
            onSelectionChanged: (value) =>
                setState(() => _isSignUp = value.first),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(labelText: context.l10n.t('email')),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty || !text.contains('@')) {
                return context.l10n.t('authErrorInvalidEmail');
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: true,
            autofillHints: [
              _isSignUp ? AutofillHints.newPassword : AutofillHints.password,
            ],
            decoration: InputDecoration(labelText: context.l10n.t('password')),
            validator: (value) => (value?.length ?? 0) < 6
                ? context.l10n.t('authErrorWeakPassword')
                : null,
          ),
          if (!_isSignUp) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _submitting ? null : _resetPassword,
                child: Text(context.l10n.t('forgotPassword')),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      context.l10n.t(_isSignUp ? 'createAccount' : 'signIn'),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Divider(color: Theme.of(context).colorScheme.outline),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  context.l10n.t('orDivider'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _submitting ? null : _submitGoogle,
              icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
              label: Text(context.l10n.t('signInWithGoogle')),
            ),
          ),
        ],
      ),
    ),
  );
}
