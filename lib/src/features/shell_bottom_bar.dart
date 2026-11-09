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
    this.bottomInset = 0,
  });

  /// 图标与文字区域的高度，不含顶部细分隔线和底部安全区。
  static const double contentHeight = 58;

  /// 顶部分隔线的宽度。它画在容器内部，会把内容再往下挤这么多。
  static const double topBorderWidth = 1;

  /// 标签栏实际占用的高度：分隔线、内容、底部安全区。
  ///
  /// 外壳按这个值给内容区和迷你播放条留位置。此前外壳按「58 + 安全区」
  /// 计算，而标签栏本身只有 58 外加 1px 分隔线，两者对不上，多出来的
  /// 安全区就变成了内容与标签栏之间的一条空白，播放条也被顶得离标签栏很远。
  static double heightWith(double bottomInset) =>
      contentHeight + topBorderWidth + bottomInset;

  final AppDestination current;
  final bool settingsOpen;
  final bool offline;
  final ValueChanged<AppDestination> onSelect;

  /// 底部安全区高度（手势条、Home 指示条）。背景铺到屏幕底边，图标与
  /// 文字抬到安全区之上，避免压住系统手势区域。
  final double bottomInset;

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
      // 背景色和分隔线一直铺到屏幕底边，图标与文字则抬到底部安全区之上，
      // 否则手势条会压住标签文字。
      padding: EdgeInsets.only(bottom: bottomInset),
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
    // 设置整页打开时，无论之前停在哪个子页，高亮都归到设置。
    if (settingsOpen) return destination == AppDestination.mine;
    return rootTabFor(current) == destination;
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
    // 未选中用中性灰而不是正文色：正文色和强调色同为深色，在浅底上
    // 明暗接近，选中与否看起来几乎一样。
    final color = selected
        ? accent
        : (context.isDark ? AppColors.slate400 : AppColors.slate500);
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: Tooltip(
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
                    // 选中底色要足够明显，纯色块比低透明度色更容易分辨。
                    color: selected
                        ? accent.withValues(alpha: context.isDark ? 0.30 : 0.16)
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
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: color,
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
