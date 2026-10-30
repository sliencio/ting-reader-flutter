import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/services/desktop_window.dart';
import '../../core/state/navigation_state.dart';
import '../../core/plugin_extensions/types.dart';
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
        {bool selected = false, Widget? leadingIcon}) {
      final leading = leadingIcon ?? Icon(icon, size: 24);
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
                  icon: leading,
                  isSelected: selected,
                  onPressed: onTap,
                ),
              )
            : ListTile(
                leading: leading,
                title: Text(title),
                selected: selected,
                onTap: onTap,
              ),
      );
    }

    Widget entry(IconData icon, String title, AppDestination destination) =>
        action(icon, title, () => widget.go(destination),
            selected: widget.currentDestination == destination);

    Widget group(List<Widget> children) => widget.compact
        ? Column(children: children)
        : Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(children: children),
          );

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
          ]),
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
          ]),
          if (app.isAdmin || widget.pluginPages.isNotEmpty)
            group([
              if (app.isAdmin) ...[
                entry(Icons.storage_rounded, context.l10n.navLibraries,
                    AppDestination.libraries),
                entry(Icons.extension_rounded, context.l10n.navPlugins,
                    AppDestination.plugins),
                entry(Icons.terminal_rounded, context.l10n.navLogs,
                    AppDestination.logs),
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
            ]),
          group([
            entry(
                Icons.info_outline_rounded,
                context.localeText('关于听悦', 'About Ting Reader'),
                AppDestination.about),
          ]),
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
