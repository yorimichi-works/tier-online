import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/browser_window.dart';
import '../widgets/common_widgets.dart';

enum _EmailActionStatus { loading, success, invalid }

class EmailActionScreen extends StatefulWidget {
  const EmailActionScreen({
    super.key,
    required this.appState,
    this.actionUri,
    this.applyActionCode,
  });

  final AppState appState;
  final Uri? actionUri;
  final Future<bool> Function(String code)? applyActionCode;

  @override
  State<EmailActionScreen> createState() => _EmailActionScreenState();
}

class _EmailActionScreenState extends State<EmailActionScreen> {
  _EmailActionStatus _status = _EmailActionStatus.loading;
  bool _started = false;
  bool _showManualCloseHint = false;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_tryApplyActionCode);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryApplyActionCode());
  }

  @override
  void dispose() {
    widget.appState.removeListener(_tryApplyActionCode);
    super.dispose();
  }

  void _tryApplyActionCode() {
    if (_started || !mounted) return;
    final handler = widget.applyActionCode;
    if (handler == null && !widget.appState.authEnabled) {
      if (widget.appState.cloudBootstrapComplete) {
        _started = true;
        setState(() => _status = _EmailActionStatus.invalid);
      }
      return;
    }

    final uri = widget.actionUri ?? Uri.base;
    final mode = uri.queryParameters['mode'];
    final code = uri.queryParameters['oobCode'] ?? '';
    if (mode != null && mode != 'verifyEmail' && code.isNotEmpty) {
      _started = true;
      final defaultHandler = Uri.https(
        'tier-online.firebaseapp.com',
        '/__/auth/action',
        uri.queryParameters,
      );
      if (!replaceBrowserLocation(defaultHandler.toString())) {
        setState(() => _status = _EmailActionStatus.invalid);
      }
      return;
    }
    if (mode != 'verifyEmail' || code.isEmpty) {
      _started = true;
      setState(() => _status = _EmailActionStatus.invalid);
      return;
    }

    _started = true;
    unawaited(_apply(handler, code));
  }

  Future<void> _apply(
    Future<bool> Function(String code)? handler,
    String code,
  ) async {
    final success =
        await (handler ?? widget.appState.applyEmailVerificationActionCode)(
          code,
        );
    if (!mounted) return;
    setState(
      () => _status = success
          ? _EmailActionStatus.success
          : _EmailActionStatus.invalid,
    );
  }

  void _close() {
    setState(() => _showManualCloseHint = true);
    if (closeBrowserWindow()) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(cropTagline: true, width: 240, height: 68),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: switch (_status) {
                        _EmailActionStatus.loading => const _LoadingContent(),
                        _EmailActionStatus.success => _ResultContent(
                          key: const ValueKey('email-action-success'),
                          icon: Icons.mark_email_read_rounded,
                          iconColor: AppColors.cyan,
                          title: context.l10n.t(
                            'emailActionVerificationComplete',
                          ),
                          message: context.l10n.t(
                            'emailActionReturnToOriginalBrowser',
                          ),
                          buttonLabel: context.l10n.t('close'),
                          onPressed: _close,
                          manualCloseHint: _showManualCloseHint
                              ? context.l10n.t('emailActionManualCloseHint')
                              : null,
                        ),
                        _EmailActionStatus.invalid => _ResultContent(
                          key: const ValueKey('email-action-invalid'),
                          icon: Icons.link_off_rounded,
                          iconColor: Theme.of(context).colorScheme.error,
                          title: context.l10n.t('emailActionInvalidTitle'),
                          message: context.l10n.t('emailActionInvalidBody'),
                          buttonLabel: context.l10n.t('close'),
                          onPressed: _close,
                          manualCloseHint: _showManualCloseHint
                              ? context.l10n.t('emailActionManualCloseHint')
                              : null,
                        ),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _LoadingContent extends StatelessWidget {
  const _LoadingContent();

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('email-action-loading'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 20),
      Text(
        context.l10n.t('emailActionVerifying'),
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _ResultContent extends StatelessWidget {
  const _ResultContent({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
    this.manualCloseHint,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;
  final String? manualCloseHint;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: .14),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 42, color: iconColor),
      ),
      const SizedBox(height: 22),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 14),
      Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.7,
        ),
      ),
      const SizedBox(height: 26),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.close_rounded),
          label: Text(buttonLabel),
        ),
      ),
      if (manualCloseHint != null) ...[
        const SizedBox(height: 12),
        Text(
          manualCloseHint!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ],
  );
}
