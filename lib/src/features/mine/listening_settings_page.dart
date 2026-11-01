import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/services/desktop_window.dart';
import '../../core/state/navigation_state.dart';
import '../../core/plugin_extensions/types.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/plugin_extensions/plugin_extension_host.dart';
import '../../core/utils/locale.dart';
import '../../shared/app_scope.dart';
import '../../shared/common/common_widgets.dart';
import '../player/desktop_window_host.dart';

const _windowBehaviorIcon = SizedBox.square(
  dimension: 24,
  child: FittedBox(child: WindowCaptionIcon(WindowCaptionAction.mini)),
);

class ListeningSettingsPage extends StatefulWidget {
  const ListeningSettingsPage({
    super.key,
    required this.go,
    this.pluginPages = const [],
    this.onOpenPluginPage,
    this.activePluginPageId,
    this.embedded = false,
    this.navigation,
    this.compact = false,
    this.currentDestination,
  });

  final ValueChanged<AppDestination> go;
  final List<ClientExtensionDescriptor> pluginPages;
  final ValueChanged<ClientExtensionDescriptor>? onOpenPluginPage;
  final String? activePluginPageId;
  final bool embedded;
  final Widget? navigation;
  final bool compact;
  final AppDestination? currentDestination;

  @override
  State<ListeningSettingsPage> createState() => _ListeningSettingsPageState();
}

class _ListeningSettingsPageState extends State<ListeningSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.appOf(context);
    Widget action(IconData icon, String title, VoidCallback? onTap,
        {bool selected = false,
        Widget? leadingIcon,
        Color? accent,
        String? subtitle}) {
      final tint = accent ?? Theme.of(context).colorScheme.primary;
      final leading = _SettingsIconBadge(
        icon: icon,
        accent: tint,
        child: leadingIcon,
      );
      return Tooltip(
        message: title,
        child: widget.compact
            ? Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: selected
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Colors.transparent,
                  ),
                  icon: leadingIcon ?? Icon(icon, size: 24),
                  isSelected: selected,
                  onPressed: onTap,
                ),
              )
            : InkWell(
                onTap: onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      leading,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : context.primaryText,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.mutedText,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: context.mutedText.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }

    Widget entry(IconData icon, String title, AppDestination destination,
            {Color? accent}) =>
        action(icon, title, () => widget.go(destination),
            selected: widget.currentDestination == destination, accent: accent);

    Widget group(List<Widget> children, {String? title}) {
      if (widget.compact) return Column(children: children);
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i++) {
        if (i > 0) {
          rows.add(Divider(
            height: 1,
            thickness: 1,
            indent: 62,
            color: context.faintBorder.withValues(alpha: 0.7),
          ));
        }
        rows.add(children[i]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: context.mutedText,
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.faintBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: context.isDark ? 0.14 : 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(children: rows),
          ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.all(widget.compact ? 8 : 16),
      children: [
        if (!widget.embedded)
          Text(context.localeText('设置', 'Settings'),
              style: Theme.of(context).textTheme.headlineMedium),
        if (widget.navigation != null) widget.navigation!,
        if (DesktopWindow.instance.supported)
          group([
            action(
                Icons.picture_in_picture_alt_rounded,
                context.localeText('窗口行为', 'Window behavior'),
                () => widget.go(AppDestination.windowSettings),
                selected:
                    widget.currentDestination == AppDestination.windowSettings,
                leadingIcon: _windowBehaviorIcon)
          ]),
        if (!app.offlineMode) ...[
          group([
            entry(
                Icons.tune_rounded,
                context.localeText('播放与外观', 'Playback & appearance'),
                AppDestination.personalization),
            entry(
                Icons.person_outline_rounded,
                context.localeText('账号与连接', 'Account & connection'),
                AppDestination.account),
            if (app.activeProfile?.isFnosGateway == true)
              entry(Icons.lan_outlined, 'FN Connect', AppDestination.fnConnect),
          ], title: context.localeText('偏好设置', 'Preferences')),
          group([
            entry(
                Icons.history_rounded,
                context.localeText('收听历史', 'Listening history'),
                AppDestination.history),
            entry(
                Icons.favorite_border_rounded,
                context.localeText('收藏', 'Favorites'),
                AppDestination.favorites),
            entry(
                Icons.bookmarks_outlined,
                context.localeText('书签', 'Bookmarks'),
                AppDestination.bookmarks),
            entry(
                Icons.playlist_play_rounded,
                context.localeText('书单', 'Playlists'),
                AppDestination.playlists),
          ], title: context.localeText('我的收藏', 'My library')),
          if (app.isAdmin || widget.pluginPages.isNotEmpty)
            group([
              if (app.isAdmin) ...[
                entry(Icons.storage_rounded, context.l10n.navLibraries,
                    AppDestination.libraries),
                entry(Icons.extension_rounded, context.l10n.navPlugins,
                    AppDestination.plugins),
                entry(Icons.terminal_rounded, context.l10n.navLogs,
                    AppDestination.logs),
                entry(
                    Icons.build_circle_outlined,
                    context.localeText('服务端维护', 'Server maintenance'),
                    AppDestination.maintenance),
                entry(Icons.group_rounded, context.l10n.navUsers,
                    AppDestination.users),
                entry(
                    Icons.notifications_none_rounded,
                    context.localeText('通知', 'Notifications'),
                    AppDestination.notifications),
                entry(
                    Icons.bar_chart_rounded,
                    context.localeText('收听统计', 'Listening statistics'),
                    AppDestination.statistics),
              ],
              for (final extension in widget.pluginPages)
                action(
                    Icons.extension_rounded,
                    extension.label,
                    widget.onOpenPluginPage == null
                        ? null
                        : () => widget.onOpenPluginPage!(extension),
                    selected: widget.activePluginPageId == extension.id,
                    leadingIcon:
                        PluginExtensionIcon(extension: extension, size: 24)),
            ], title: context.localeText('服务端管理', 'Server management')),
          group([
            entry(
                Icons.info_outline_rounded,
                context.localeText('关于听悦', 'About Ting Reader'),
                AppDestination.about),
          ], title: context.localeText('其他', 'More')),
        ],
        group([
          action(
              Icons.logout_rounded,
              app.offlineMode
                  ? context.l10n.navReturnLogin
                  : context.localeText('切换账号或服务器', 'Switch account or server'),
              app.logout),
          if (DesktopWindow.instance.supported)
            action(
                Icons.power_settings_new_rounded,
                context.localeText('退出软件', 'Exit application'),
                DesktopWindow.instance.requestExit),
        ]),
      ],
    );
  }
}

/// 设置项的圆角图标徽章：浅色底加同色系图标，比裸图标更容易扫读。
class _SettingsIconBadge extends StatelessWidget {
  const _SettingsIconBadge({
    required this.icon,
    required this.accent,
    this.child,
  });

  final IconData icon;
  final Color accent;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: context.isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: SizedBox.square(
        dimension: 20,
        child: child != null
            ? FittedBox(child: child)
            : Icon(icon, size: 19, color: accent),
      ),
    );
  }
}

class WindowSettingsPage extends StatefulWidget {
  const WindowSettingsPage({super.key});

  @override
  State<WindowSettingsPage> createState() => _WindowSettingsPageState();
}

class _WindowSettingsPageState extends State<WindowSettingsPage> {
  bool _saving = false;

  Future<void> _save(String? value) async {
    if (value == null || _saving) return;
    final app = AppScope.appOf(context);
    setState(() => _saving = true);
    try {
      await app.updateLocalSettings({'desktop_close_behavior': value});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiError.messageFor(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.appOf(context);
    final stored = app.settings['desktop_close_behavior']?.toString();
    final current = ['exit', 'minimize'].contains(stored) ? stored! : 'ask';
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: PageListView(children: [
          HeaderText(
              iconWidget: _windowBehaviorIcon,
              title: context.localeText('窗口行为', 'Window behavior'),
              subtitle:
                  context.localeText('点击关闭按钮时', 'When closing the window')),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: RadioGroup<String>(
              groupValue: current,
              onChanged: _save,
              child: Column(children: [
                RadioListTile<String>(
                    value: 'ask',
                    enabled: !_saving,
                    title: Text(context.localeText('每次询问', 'Ask every time'))),
                RadioListTile<String>(
                    value: 'exit',
                    enabled: !_saving,
                    title: Text(context.localeText('直接退出', 'Exit'))),
                RadioListTile<String>(
                    value: 'minimize',
                    enabled: !_saving,
                    title: Text(
                        context.localeText('最小化到任务栏', 'Minimize to taskbar'))),
              ]),
            ),
          ),
          const SafeBottomSpacer(),
        ]),
      ),
    );
  }
}
