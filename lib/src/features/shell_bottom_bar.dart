import 'package:flutter/material.dart';

import '../core/state/navigation_state.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/locale.dart';

/// 移动端底部导航。
///
/// 图标与文字始终同时可见，替代此前 72px 宽的纯图标侧栏：那条侧栏在手机上
/// 放不下文字，用户只能看到齿轮和几个方块，不知道每个按钮是做什么的。
class ShellBottomBar extends StatelessWidget {
  const ShellBottomBar({
    super.key,
    required this.current,
    required this.settingsOpen,
    required this.offline,
    required this.onSelect,
  });

  final AppDestination current;
  final bool settingsOpen;
  final bool offline;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final entries = <_Tab>[
      _Tab(
        destination: AppDestination.bookshelf,
        icon: Icons.auto_stories_outlined,
        activeIcon: Icons.auto_stories_rounded,
        label: context.l10n.navBookshelf,
      ),
      _Tab(
        destination: AppDestination.downloads,
        icon: Icons.download_outlined,
        activeIcon: Icons.download_rounded,
        label: context.l10n.navDownloads,
      ),
      _Tab(
        destination: AppDestination.mine,
        icon: Icons.tune_rounded,
        activeIcon: Icons.tune_rounded,
        label: context.localeText('设置', 'Settings'),
      ),
    ];
    final visible = offline
        ? entries
            .where((tab) => tab.destination != AppDestination.bookshelf)
            .toList(growable: false)
        : entries;

    return Container(
      decoration: BoxDecoration(
        color: context.isDark ? AppColors.slate900 : Colors.white,
        border: Border(top: BorderSide(color: context.faintBorder)),
      ),
      child: Row(
        children: [
          for (final tab in visible)
            Expanded(
              child: _TabButton(
                tab: tab,
                selected: _matches(tab.destination),
                onTap: () => onSelect(tab.destination),
              ),
            ),
        ],
      ),
    );
  }

  /// 设置页会先把导航切回书架再展开，这里按「设置是否打开」判断，
  /// 避免打开设置后底部高亮跳回书架。
  bool _matches(AppDestination destination) {
    if (destination == AppDestination.mine) {
      return current == AppDestination.mine ||
          current == AppDestination.personalization ||
          current == AppDestination.account;
    }
    return current == destination;
  }
}

class _Tab {
  const _Tab({
    required this.destination,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final AppDestination destination;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final color = selected ? accent : context.mutedText;
    return Tooltip(
      message: tab.label,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: SizedBox(
          height: 58,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: context.isDark ? 0.22 : 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Icon(
                  selected ? tab.activeIcon : tab.icon,
                  size: 22,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
