import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/app_breakpoints.dart';

/// Adds browser-style middle-mouse auto scrolling to a Flutter scroll view.
///
/// Flutter Web renders inside a canvas, so the browser cannot discover the
/// inner [Scrollable] that should react to a pressed mouse wheel. Holding the
/// middle button and moving above or below the press point scrolls the supplied
/// controller continuously. Touch, left-button dragging and item DnD remain
/// untouched.
class MiddleMouseAutoScroll extends StatefulWidget {
  const MiddleMouseAutoScroll({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  State<MiddleMouseAutoScroll> createState() => _MiddleMouseAutoScrollState();
}

class WorldLanguageFilter extends StatelessWidget {
  const WorldLanguageFilter({
    super.key,
    required this.enabled,
    required this.selected,
    required this.onEnabledChanged,
    required this.onLanguageChanged,
  });

  final bool enabled;
  final Set<AppLocale> selected;
  final ValueChanged<bool> onEnabledChanged;
  final void Function(AppLocale locale, bool selected) onLanguageChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: BorderSide(color: Theme.of(context).colorScheme.outline),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(13, 5, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            value: enabled,
            onChanged: (value) => onEnabledChanged(value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(
              context.l10n.t('viewWorldTiers'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              context.l10n.t('viewWorldTiersHelp'),
              style: const TextStyle(fontSize: 11),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: enabled
                ? Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final locale in AppLocale.values)
                          FilterChip(
                            selected: selected.contains(locale),
                            showCheckmark: true,
                            label: Text(context.l10n.languageName(locale)),
                            onSelected: (value) =>
                                onLanguageChanged(locale, value),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}

class _MiddleMouseAutoScrollState extends State<MiddleMouseAutoScroll> {
  Offset? _lastPointer;

  bool get _active => _lastPointer != null;

  void _start(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons & kMiddleMouseButton == 0) {
      return;
    }
    _lastPointer = event.position;
    setState(() {});
  }

  void _move(PointerMoveEvent event) {
    if (!_active) return;
    if (event.buttons & kMiddleMouseButton == 0) {
      _stop();
      return;
    }
    final previous = _lastPointer!;
    _lastPointer = event.position;
    if (!widget.controller.hasClients) return;
    final delta = event.position.dy - previous.dy;
    final position = widget.controller.position;
    final target = (position.pixels - delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) position.jumpTo(target);
  }

  void _stop() {
    if (!_active) return;
    _lastPointer = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: _active ? SystemMouseCursors.grabbing : MouseCursor.defer,
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _start,
      onPointerMove: _move,
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: widget.child,
    ),
  );
}

class ContentFrame extends StatelessWidget {
  const ContentFrame({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.contentMaxWidth,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 32),
  });
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: padding,
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      if (actionLabel != null)
        TextButton(onPressed: onAction, child: Text(actionLabel!)),
    ],
  );
}

class CategoryFilterChip extends StatelessWidget {
  const CategoryFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? AppColors.background
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? AppColors.cyan : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? AppColors.cyan
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check_rounded, size: 17, color: foreground),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  softWrap: false,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });
  final String title;
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        const SizedBox(height: 7),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.showName = true,
    this.cropTagline = false,
    this.width,
    this.height,
  });
  final bool showName;
  final bool cropTagline;
  final double? width;
  final double? height;

  String _assetFor(AppLocale locale) => switch (locale) {
    AppLocale.ja => 'assets/branding/tier-logo.png',
    AppLocale.ko => 'assets/branding/tier-logo-ko.png',
    AppLocale.zhTw => 'assets/branding/tier-logo-en.png',
    AppLocale.ptBr => 'assets/branding/tier-logo-en.png',
    AppLocale.en => 'assets/branding/tier-logo-en.png',
  };

  @override
  Widget build(BuildContext context) {
    final locale = context.l10n.locale;
    final asset = _assetFor(locale);
    final fit = cropTagline ? BoxFit.fitWidth : BoxFit.contain;
    final alignment = cropTagline ? Alignment.topLeft : Alignment.centerLeft;
    Widget logo({Key? key}) => Image.asset(
      asset,
      key: key,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
    final light = Theme.of(context).brightness == Brightness.light;
    return Semantics(
      label: context.l10n.t('appName'),
      image: true,
      child: SizedBox(
        width: width ?? (showName ? 168 : 52),
        height: height ?? (showName ? 54 : 44),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            if (light)
              Positioned.fill(
                key: const ValueKey('brand-shadow'),
                child: Transform.translate(
                  offset: const Offset(0, 2),
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Color(0xB8000000),
                        BlendMode.srcIn,
                      ),
                      child: logo(),
                    ),
                  ),
                ),
              ),
            ClipRect(child: logo(key: ValueKey('brand-logo-${locale.code}'))),
          ],
        ),
      ),
    );
  }
}
