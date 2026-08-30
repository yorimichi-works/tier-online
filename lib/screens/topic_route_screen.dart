import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tier_models.dart';
import '../services/app_state.dart';
import '../widgets/common_widgets.dart';
import 'topic_detail_screen.dart';

class TopicRouteScreen extends StatefulWidget {
  const TopicRouteScreen({
    super.key,
    required this.appState,
    required this.topicId,
    required this.onTagTap,
  });

  final AppState appState;
  final String topicId;
  final ValueChanged<String?> onTagTap;

  @override
  State<TopicRouteScreen> createState() => _TopicRouteScreenState();
}

class _TopicRouteScreenState extends State<TopicRouteScreen> {
  TierTopic? _topic;
  Object? _error;
  bool _requesting = false;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_handleAppStateChanged);
    _resolve();
  }

  @override
  void didUpdateWidget(covariant TopicRouteScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState != widget.appState) {
      oldWidget.appState.removeListener(_handleAppStateChanged);
      widget.appState.addListener(_handleAppStateChanged);
    }
    if (oldWidget.topicId != widget.topicId) {
      _topic = null;
      _error = null;
      _requesting = false;
      _notFound = false;
      _resolve();
    }
  }

  @override
  void dispose() {
    widget.appState.removeListener(_handleAppStateChanged);
    super.dispose();
  }

  void _handleAppStateChanged() => _resolve();

  void _resolve() {
    if (!mounted || _requesting || _topic != null || _notFound) return;
    final existing = widget.appState.topicById(widget.topicId);
    if (existing != null &&
        (widget.topicId.startsWith('starter-') ||
            widget.appState.trustLocalSharedRoutes)) {
      setState(() {
        _topic = existing;
        _error = null;
        _notFound = false;
      });
      return;
    }
    if (!widget.appState.cloudEnabled) {
      if (widget.appState.cloudBootstrapComplete) {
        // A failed/offline Firebase bootstrap is not proof that the topic was
        // deleted. Keep the device cache and offer retry instead.
        setState(() => _error = StateError('Cloud validation unavailable'));
      }
      return;
    }
    _requesting = true;
    unawaited(_loadFromCloud());
  }

  Future<void> _loadFromCloud() async {
    try {
      final topic = await widget.appState.loadTopicById(widget.topicId);
      if (!mounted) return;
      setState(() {
        _topic = topic;
        _notFound = topic == null;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      _requesting = false;
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _notFound = false;
    });
    _resolve();
  }

  @override
  Widget build(BuildContext context) {
    final topic = _topic;
    if (topic != null) {
      return TopicDetailScreen(
        appState: widget.appState,
        topic: topic,
        onTagTap: widget.onTagTap,
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.t('appName'))),
      body: ContentFrame(
        maxWidth: 560,
        child: Center(
          child: _error != null
              ? _RouteMessage(
                  icon: Icons.cloud_off_outlined,
                  title: context.l10n.t('tierLoadFailed'),
                  actionLabel: context.l10n.t('retry'),
                  onAction: _retry,
                )
              : _notFound
              ? _RouteMessage(
                  icon: Icons.search_off_rounded,
                  title: context.l10n.t('tierDeletedOrPrivate'),
                  actionLabel: context.l10n.t('home'),
                  onAction: () => Navigator.of(
                    context,
                  ).pushReplacementNamed('/${widget.appState.locale.code}/'),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(context.l10n.t('loadingTier')),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RouteMessage extends StatelessWidget {
  const _RouteMessage({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 48),
      const SizedBox(height: 14),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 18),
      FilledButton(onPressed: onAction, child: Text(actionLabel)),
    ],
  );
}
