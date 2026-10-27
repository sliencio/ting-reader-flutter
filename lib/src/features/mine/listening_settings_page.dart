import 'package:flutter/material.dart';

import '../../core/state/navigation_state.dart';
import '../../core/utils/locale.dart';
import '../../shared/app_scope.dart';
import '../../shared/common/common_widgets.dart';

class ListeningSettingsPage extends StatelessWidget {
  const ListeningSettingsPage({
    super.key,
    required this.go,
    required this.openManagement,
    required this.hasPluginPages,
  });

  final ValueChanged<AppDestination> go;
  final VoidCallback openManagement;
  final bool hasPluginPages;

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
            Text(
              context.localeText('设置', 'Settings'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
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
            ]),
            const SafeBottomSpacer(),
          ],
        ),
      ),
    );
  }
}
