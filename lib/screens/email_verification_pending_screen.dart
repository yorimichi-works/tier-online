import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_state.dart';

const _resendCooldownSeconds = 60;

class EmailVerificationPendingScreen extends StatefulWidget {
  const EmailVerificationPendingScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<EmailVerificationPendingScreen> createState() =>
      _EmailVerificationPendingScreenState();
}

class _EmailVerificationPendingScreenState
    extends State<EmailVerificationPendingScreen> {
  bool _checking = false;
  bool _resending = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = _resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldown -= 1;
        if (_cooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _checkVerification() async {
    setState(() => _checking = true);
    final verified = await widget.appState.refreshEmailVerified();
    if (!mounted) return;
    setState(() => _checking = false);
    final messenger = ScaffoldMessenger.of(context);
    if (verified) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.t('verificationCompleted'))),
      );
      Navigator.of(context).pop();
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(context.l10n.t('verificationNotCompleted'))),
    );
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    final ok = await widget.appState.resendVerificationEmail();
    if (!mounted) return;
    setState(() => _resending = false);
    _startCooldown();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.t(
            ok ? 'verificationEmailResent' : 'verificationEmailSendFailed',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.appState.userEmail ?? '';
    final canResend = !_resending && _cooldown <= 0;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.mark_email_unread_rounded,
                    size: 64,
                    color: Colors.amber,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    context.l10n.t('verifyEmailTitle'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.t('verifyEmailDescription'),
                    textAlign: TextAlign.center,
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      email,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _checking ? null : _checkVerification,
                    child: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(context.l10n.t('checkVerification')),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: canResend ? _resend : null,
                    child: Text(
                      canResend
                          ? context.l10n.t('resendVerificationEmail')
                          : '${context.l10n.t('resendVerificationEmail')} ($_cooldown${context.l10n.t('verificationResendCooldown')})',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      context.l10n.t('verifyEmailNoticeTitle'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('・${context.l10n.t('checkSpamFolder')}'),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('・${context.l10n.t('checkEmailAddress')}'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
