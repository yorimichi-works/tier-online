import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/app_breakpoints.dart';
import '../widgets/adsense_ad.dart';
import '../widgets/common_widgets.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.index,
    required this.onSelected,
    required this.scrollController,
    required this.body,
  });
  final int index;
  final ValueChanged<int> onSelected;
  final ScrollController scrollController;
  final Widget body;
  static List<NavigationDestination> destinations(BuildContext context) => [
    NavigationDestination(
      icon: const Icon(Icons.home_outlined),
      selectedIcon: const Icon(Icons.home_rounded),
      label: context.l10n.t('home'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.search_rounded),
      selectedIcon: const Icon(Icons.manage_search_rounded),
      label: context.l10n.t('explore'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.add_circle_outline_rounded),
      selectedIcon: const Icon(Icons.add_circle_rounded),
      label: context.l10n.t('create'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.view_agenda_outlined),
      selectedIcon: const Icon(Icons.view_agenda_rounded),
      label: context.l10n.t('myTier'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.settings_outlined),
      selectedIcon: const Icon(Icons.settings_rounded),
      label: context.l10n.t('settings'),
    ),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = AppBreakpoints.isDesktop(constraints.maxWidth);
      if (desktop) {
        return _DesktopPortalScaffold(
          width: constraints.maxWidth,
          index: index,
          onSelected: onSelected,
          scrollController: scrollController,
          body: body,
        );
      }
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 72,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const BrandMark(cropTagline: true, width: 190, height: 50),
                    const Spacer(),
                    IconButton(
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.l10n.t('guestMessage')),
                            ),
                          ),
                      icon: const Icon(Icons.person_outline_rounded),
                      tooltip: context.l10n.t('guest'),
                    ),
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: onSelected,
          destinations: destinations(context),
        ),
      );
    },
  );
}

class _DesktopPortalScaffold extends StatelessWidget {
  const _DesktopPortalScaffold({
    required this.width,
    required this.index,
    required this.onSelected,
    required this.scrollController,
    required this.body,
  });

  final double width;
  final int index;
  final ValueChanged<int> onSelected;
  final ScrollController scrollController;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final showAds = width >= 1280;
    final adWidth = showAds
        ? ((width - 1040 - 32) / 2).clamp(150.0, 280.0)
        : 0.0;
    final portalWidth = showAds
        ? (width - adWidth * 2 - 32).clamp(900.0, 1040.0)
        : width.clamp(900.0, 1040.0);
    return Scaffold(
      body: SafeArea(
        child: ScrollbarTheme(
          data: ScrollbarThemeData(
            thumbColor: const WidgetStatePropertyAll(AppColors.cyan),
            trackColor: const WidgetStatePropertyAll(Color(0xFF17171B)),
            trackBorderColor: const WidgetStatePropertyAll(AppColors.outline),
            thickness: const WidgetStatePropertyAll(11),
            radius: const Radius.circular(8),
          ),
          child: Scrollbar(
            controller: scrollController,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            child: ColoredBox(
              color: const Color(0xFF08080A),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showAds) ...[
                      SizedBox(
                        width: adWidth,
                        child: const _DesktopAdSlot(side: _AdSide.left),
                      ),
                      const SizedBox(width: 16),
                    ],
                    SizedBox(
                      width: portalWidth,
                      child: _DesktopPortal(
                        index: index,
                        onSelected: onSelected,
                        body: MiddleMouseAutoScroll(
                          controller: scrollController,
                          child: body,
                        ),
                      ),
                    ),
                    if (showAds) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: adWidth,
                        child: const _DesktopAdSlot(side: _AdSide.right),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopPortal extends StatelessWidget {
  const _DesktopPortal({
    required this.index,
    required this.onSelected,
    required this.body,
  });

  final int index;
  final ValueChanged<int> onSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.symmetric(vertical: BorderSide(color: colors.outline)),
        ),
        child: Column(
          children: [
            Container(
              height: 96,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(bottom: BorderSide(color: colors.outline)),
              ),
              child: Row(
                children: [
                  const BrandMark(cropTagline: true, width: 300, height: 78),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      context.l10n.t('tagline'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => onSelected(2),
                    icon: const Icon(Icons.add_circle_rounded, size: 21),
                    label: Text(context.l10n.t('createTier')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(146, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      backgroundColor: AppColors.purple,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.t('anonymousMessage')),
                      ),
                    ),
                    icon: const Icon(Icons.account_circle_outlined),
                    tooltip: context.l10n.t('account'),
                  ),
                ],
              ),
            ),
            Container(
              height: 66,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              color: colors.surfaceContainerHigh,
              child: Row(
                children: [
                  for (
                    var i = 0;
                    i < AppScaffold.destinations(context).length;
                    i++
                  )
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _DesktopTopNavItem(
                          destination: AppScaffold.destinations(context)[i],
                          selected: index == i,
                          onTap: () => onSelected(i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 184,
                    child: _DesktopSideMenu(
                      index: index,
                      onSelected: onSelected,
                    ),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopTopNavItem extends StatelessWidget {
  const _DesktopTopNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });
  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: Material(
      color: selected
          ? AppColors.purple.withValues(alpha: .28)
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(
          color: selected
              ? AppColors.cyan
              : Theme.of(context).colorScheme.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(
                data: IconThemeData(
                  size: 19,
                  color: selected ? AppColors.cyan : const Color(0xFF8F8F9B),
                ),
                child: selected
                    ? destination.selectedIcon ?? destination.icon
                    : destination.icon,
              ),
              const SizedBox(width: 8),
              Text(
                destination.label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFB3B3BE),
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DesktopSideMenu extends StatelessWidget {
  const _DesktopSideMenu({required this.index, required this.onSelected});
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(9, 0, 9, 10),
          child: Text(
            context.l10n.t('menu'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
        for (var i = 0; i < AppScaffold.destinations(context).length; i++)
          _DesktopSideMenuItem(
            icon: i == index
                ? AppScaffold.destinations(context)[i].selectedIcon ??
                      AppScaffold.destinations(context)[i].icon
                : AppScaffold.destinations(context)[i].icon,
            label: AppScaffold.destinations(context)[i].label,
            selected: i == index,
            onTap: () => onSelected(i),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Divider(height: 1),
        ),
        Material(
          color: AppColors.purple,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelected(2),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.bolt_rounded, color: Colors.white, size: 24),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.t('createNewTier'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    context.l10n.t('createHint'),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFE8E6FF),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.t('startCreating'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _DesktopSideMenuItem extends StatelessWidget {
  const _DesktopSideMenuItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final Widget icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Material(
      color: selected
          ? AppColors.purple.withValues(alpha: .18)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(
            children: [
              IconTheme(
                data: IconThemeData(
                  size: 19,
                  color: selected ? AppColors.cyan : const Color(0xFFA7A7B3),
                ),
                child: icon,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
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

enum _AdSide { left, right }

class _DesktopAdSlot extends StatelessWidget {
  const _DesktopAdSlot({required this.side});
  final _AdSide side;

  static const _fallbackSlot = String.fromEnvironment('ADSENSE_SLOT');
  static const _leftSlot = String.fromEnvironment(
    'ADSENSE_LEFT_SLOT',
    defaultValue: _fallbackSlot,
  );
  static const _rightSlot = String.fromEnvironment(
    'ADSENSE_RIGHT_SLOT',
    defaultValue: _fallbackSlot,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxHeight >= 760
          ? 720.0
          : (constraints.maxHeight - 24).clamp(360.0, 720.0);
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: side == _AdSide.left
                    ? const [Color(0xFF24204A), Color(0xFF101525)]
                    : const [Color(0xFF173945), Color(0xFF111B22)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outline),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      color: Colors.black.withValues(alpha: .22),
                      alignment: Alignment.center,
                      child: Text(
                        context.l10n.t('ad'),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF8C8C98),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.campaign_outlined,
                        size: 34,
                        color: Color(0xFF777784),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.t('adSpace'),
                      style: const TextStyle(
                        color: Color(0xFFB5B5C0),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'WIDE SKYSCRAPER',
                      style: TextStyle(
                        color: Color(0xFF70707C),
                        fontSize: 9,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                AdSenseAd(slot: side == _AdSide.left ? _leftSlot : _rightSlot),
              ],
            ),
          ),
        ),
      );
    },
  );
}
