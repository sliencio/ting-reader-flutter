import 'package:flutter/material.dart';

import '../../core/state/navigation_state.dart';
import '../../core/utils/locale.dart';
import '../../shared/app_scope.dart';
import '../../shared/common/common_widgets.dart';
import '../../core/services/desktop_window.dart';
import '../../core/api/api_error.dart';

class ListeningSettingsPage extends StatefulWidget {
  const ListeningSettingsPage({
    super.key,
    required this.go,
    required this.openManagement,
    required this.hasPluginPages,
    required this.forceRefresh,
    this.embedded = false,
    this.navigation,
  });

  final ValueChanged<AppDestination> go;
  final VoidCallback openManagement;
  final bool hasPluginPages;
  final Future<void> Function() forceRefresh;
  final bool embedded;
  final Widget? navigation;

  @override
  State<ListeningSettingsPage> createState() => _ListeningSettingsPageState();
}

class _ListeningSettingsPageState extends State<ListeningSettingsPage> {
  bool _refreshing = false;
  ValueChanged<AppDestination> get go => widget.go;
  VoidCallback get openManagement => widget.openManagement;
  bool get hasPluginPages => widget.hasPluginPages;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.forceRefresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiError.messageFor(error))));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.appOf(context);
    Widget entry(
      IconData icon,
      String title,
      AppDestination destination, {
      String? subtitle,
    }) {
      return ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => go(destination),
      );
    }

    Widget group(List<Widget> children) => Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.only(bottom: 20),
          child: Column(children: children),
        );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: PageListView(
          children: [
            if (!widget.embedded)
              Text(
                context.localeText('设置', 'Settings'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            if (!widget.embedded) const SizedBox(height: 24),
            if (widget.navigation != null) widget.navigation!,
            if (DesktopWindow.instance.supported)
              group([
                ListTile(
                    leading: const Icon(Icons.picture_in_picture_alt_rounded),
                    title: Text(context.localeText('小窗模式', 'Mini window')),
                    subtitle: Text(context.localeText(
                        '置顶显示播放器', 'Keep the player on top')),
                    onTap: () => DesktopWindow.instance.setMini(true)),
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(app.settings['desktop_close_behavior']),
                      initialValue:
                          app.settings['desktop_close_behavior']?.toString() ??
                              'ask',
                      decoration: InputDecoration(
                          labelText: context.localeText(
                              '点击关闭按钮时', 'When closing the window')),
                      items: [
                        DropdownMenuItem(
                            value: 'ask',
                            child: Text(
                                context.localeText('每次询问', 'Ask every time'))),
                        DropdownMenuItem(
                            value: 'exit',
                            child: Text(context.localeText('直接退出', 'Exit'))),
                        DropdownMenuItem(
                            value: 'minimize',
                            child: Text(context.localeText(
                                '最小化到任务栏', 'Minimize to taskbar'))),
                      ],
                      onChanged: (value) async {
                        if (value != null) {
                          await app.updateLocalSettings(
                              {'desktop_close_behavior': value});
                        }
                      },
                    )),
              ]),
            group([
              ListTile(
                  leading: _refreshing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync_rounded),
                  title: Text(context.localeText('强制刷新', 'Force refresh')),
                  subtitle: Text(context.localeText('清除书架与详情缓存，重新获取服务端信息',
                      'Clear shelf and detail caches and reload server data')),
                  onTap: _refreshing ? null : _refresh),
            ]),
            group([
              entry(
                Icons.tune_rounded,
                context.localeText('播放与外观', 'Playback & appearance'),
                AppDestination.personalization,
              ),
              entry(
                Icons.person_outline_rounded,
                context.localeText('账号与连接', 'Account & connection'),
                AppDestination.account,
                subtitle: app.user?.username,
              ),
              if (app.activeProfile?.isFnosGateway == true)
                entry(
                    Icons.lan_outlined, 'FN Connect', AppDestination.fnConnect),
            ]),
            group([
              entry(
                Icons.history_rounded,
                context.localeText('收听历史', 'Listening history'),
                AppDestination.history,
              ),
              entry(
                Icons.favorite_border_rounded,
                context.localeText('收藏', 'Favorites'),
                AppDestination.favorites,
              ),
              entry(
                Icons.bookmarks_outlined,
                context.localeText('书签', 'Bookmarks'),
                AppDestination.bookmarks,
              ),
              entry(
                Icons.playlist_play_rounded,
                context.localeText('书单', 'Playlists'),
                AppDestination.playlists,
              ),
            ]),
            if (app.isAdmin || hasPluginPages)
              group([
                ExpansionTile(
                  leading: const Icon(Icons.more_horiz_rounded),
                  title: Text(context.localeText('高级功能', 'Advanced')),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: Text(
                        context.localeText('服务端管理与扩展', 'Server & extensions'),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: openManagement,
                    ),
                    if (app.isAdmin) ...[
                      entry(
                        Icons.notifications_none_rounded,
                        context.localeText('通知', 'Notifications'),
                        AppDestination.notifications,
                      ),
                      entry(
                        Icons.bar_chart_rounded,
                        context.localeText('收听统计', 'Listening statistics'),
                        AppDestination.statistics,
                      ),
                    ],
                  ],
                ),
              ]),
            group([
              entry(
                Icons.info_outline_rounded,
                context.localeText('关于听悦', 'About Ting Reader'),
                AppDestination.about,
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: Text(
                    context.localeText('切换账号或服务器', 'Switch account or server')),
                onTap: app.logout,
              ),
              if (DesktopWindow.instance.supported)
                ListTile(
                  leading: const Icon(Icons.power_settings_new_rounded),
                  title: Text(context.localeText('退出软件', 'Exit application')),
                  onTap: DesktopWindow.instance.requestExit,
                ),
            ]),
            const SafeBottomSpacer(),
          ],
        ),
      ),
    );
  }
}
