import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin/admin_pages.dart';
import 'admin/users/admin_users_page.dart';
import 'bookshelf/book_detail/book_detail_page.dart';
import 'bookshelf/bookshelf_page.dart';
import 'bookshelf/search_page.dart';
import 'bookshelf/series_detail/series_detail_page.dart';
import 'home/home_page.dart';
import 'mine/about_update_dialog.dart';
import 'mine/downloads_page.dart';
import 'mine/favorites_page.dart';
import 'mine/fn_connect_page.dart';
import 'mine/mine_page.dart';
import 'mine/listening_settings_page.dart';
import 'mine/server_maintenance_page.dart';
import 'mine/history_page.dart';
import 'mine/bookmarks_page.dart';
import 'mine/personalization/personalization_page.dart';
import 'playlists/playlists_page.dart';
import '../core/models/models.dart';
import '../core/services/desktop_window.dart';
import '../core/state/app_state.dart';
import '../core/state/navigation_state.dart';
import '../core/state/player_state.dart';
import '../core/plugin_extensions/types.dart';
import '../core/utils/locale.dart';
import '../shared/app_scope.dart';
import '../shared/common/common_widgets.dart';
import '../shared/plugin_extensions/plugin_extension_host.dart';
import 'player/mini_player.dart';
import 'settings_push_layout.dart';
import 'shell_bottom_bar.dart';

typedef _NavigationEntry = ({
  AppDestination destination,
  IconData icon,
  String label,
});

List<_NavigationEntry> _navigationEntries(BuildContext context) {
  final l10n = context.l10n;
  return [
    (
      destination: AppDestination.bookshelf,
      icon: Icons.library_books_rounded,
      label: l10n.navBookshelf,
    ),
    (
      destination: AppDestination.downloads,
      icon: Icons.download_outlined,
      label: l10n.navDownloads,
    ),
    (
      destination: AppDestination.mine,
      icon: Icons.settings_outlined,
      label: context.localeText('设置', 'Settings'),
    ),
  ];
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final ShellNavigation _navigation;
  static const _primaryDestinations = [
    AppDestination.bookshelf,
    AppDestination.downloads,
  ];
  final Map<AppDestination, Widget> _primaryPages = {};
  String? _pageIdentity;
  AppDestination get _destination => _navigation.destination;
  AppDestination get _searchOrigin => _navigation.searchOrigin;
  String? get _bookId => _navigation.bookId;
  String? get _bookInitialChapterId => _navigation.chapterId;
  String? get _seriesId => _navigation.seriesId;
  String? get _playlistId => _navigation.playlistId;
  String? get _aboutBackendVersion => _navigation.aboutBackendVersion;
  ClientExtensionDescriptor? get _activePluginPage =>
      _navigation.activePluginPage;
  PluginItem? get _activePluginLogs => _navigation.activePluginLogs;
  bool _settingsOpen = false;
  bool _settingsCreated = false;
  final _settingsMessengerKey = GlobalKey<ScaffoldMessengerState>();
  ClientExtensionRegistrySnapshot get _pluginRegistry =>
      AppScope.appOf(context).clientExtensions.snapshot;
  String? _defaultCredentialsReminderIdentity;

  @override
  void initState() {
    super.initState();
    _navigation = ShellNavigation.fromQuery(Uri.base.queryParameters);
    if (_navigation.destination == AppDestination.mine) {
      _navigation.go(AppDestination.bookshelf);
      _settingsOpen = _settingsCreated = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = AppScope.appOf(context);
    _remindDefaultAdminCredentials();
    appState.ensureClientExtensions();
    if (appState.offlineMode || appState.token == null) {
      _navigation.activePluginPage = null;
      _navigation.activePluginLogs = null;
      return;
    }
    final active = _activePluginPage;
    if (active != null && !appState.clientExtensions.loading) {
      _navigation.activePluginPage =
          _sidebarPluginPages.where((item) => item.id == active.id).firstOrNull;
    }
    _restoreInitialPluginPage();
  }

  void _remindDefaultAdminCredentials() {
    final appState = AppScope.appOf(context);
    final user = appState.user;
    if (appState.offlineMode ||
        !appState.isAuthenticated ||
        user == null ||
        !user.isAdmin ||
        !user.usesDefaultAdminCredentials) {
      return;
    }
    final identity = '${appState.serverUrl}:${user.id}';
    if (_defaultCredentialsReminderIdentity == identity) return;
    _defaultCredentialsReminderIdentity = identity;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final current = AppScope.appOf(context);
      if (current.offlineMode ||
          '${current.serverUrl}:${current.user?.id}' != identity ||
          current.user?.usesDefaultAdminCredentials != true) {
        return;
      }
      final changeCredentials = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.security_rounded),
          title: Text(dialogContext.l10n.authDefaultCredentialsTitle),
          content: Text(dialogContext.l10n.authDefaultCredentialsMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.l10n.authDefaultCredentialsLater),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogContext.l10n.authDefaultCredentialsChange),
            ),
          ],
        ),
      );
      if (!mounted || changeCredentials != true) return;
      final active = AppScope.appOf(context);
      if ('${active.serverUrl}:${active.user?.id}' != identity) return;
      AppScope.playerOf(context).setExpanded(false);
      _go(AppDestination.account);
    });
  }

  List<ClientExtensionDescriptor> get _sidebarPluginPages {
    final appState = AppScope.appOf(context);
    final extensions =
        _pluginRegistry.bySlot[ClientExtensionSlot.appSidebarPage] ?? const [];
    return extensions
        .where((extension) => !extension.adminOnly || appState.isAdmin)
        .toList(growable: false);
  }

  void _restoreInitialPluginPage() {
    if (_destination != AppDestination.pluginPage ||
        _activePluginPage != null) {
      return;
    }
    final pluginId = _navigation.initialPluginId;
    final capabilityId = _navigation.initialCapabilityId;
    if (pluginId == null || capabilityId == null) return;
    for (final extension in _sidebarPluginPages) {
      if (extension.pluginId == pluginId &&
          extension.capability.id == capabilityId) {
        _navigation.activePluginPage = extension;
        return;
      }
    }
  }

  void _navigate(VoidCallback change) {
    setState(() {
      change();
    });
    if (hidesMiniPlayer(_navigation.navDestination)) {
      AppScope.playerOf(context).setExpanded(false);
    }
  }

  void _go(AppDestination destination) {
    if (destination == AppDestination.mine) {
      if (_navigation.backDestination == AppDestination.mine) {
        _navigation.go(AppDestination.bookshelf);
      }
      _openSettings();
      return;
    }
    _navigate(() => _navigation.go(destination));
  }

  void _openSettings() => setState(() {
        _settingsOpen = _settingsCreated = true;
      });

  void _closeSettings() => setState(() => _settingsOpen = false);

  void _goHome() {
    FocusManager.instance.primaryFocus?.unfocus();
    _navigate(() {
      _navigation.go(AppDestination.bookshelf);
      _settingsOpen = false;
    });
  }

  Widget _homeButton() => IconButton(
        tooltip: context.localeText('返回主页', 'Home'),
        icon: const Icon(Icons.home_outlined),
        onPressed: _goHome,
      );
  void _openPluginLogs(PluginItem plugin) =>
      _navigate(() => _navigation.openPluginLogs(plugin));
  void _openPluginPage(ClientExtensionDescriptor extension) =>
      _navigate(() => _navigation.openPluginPage(extension));
  void _openAbout(String? version) =>
      _navigate(() => _navigation.openAbout(version));

  Future<void> _forceRefresh() async {
    final app = AppScope.appOf(context);
    await app.loadSettings();
    if (!mounted) return;
    app.bookDetailsCache.clear();
    await app.coverCache.invalidate();
    if (!mounted) return;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    setState(_primaryPages.clear);
  }

  void _openBook(String id) => _openBookAtChapter(id, null);
  void _openBookAtChapter(String id, String? chapterId) => _navigate(
        () => _navigation.openDetail(DetailDestination.book, id,
            chapter: chapterId),
      );
  void _openSeries(String id) =>
      _navigate(() => _navigation.openDetail(DetailDestination.series, id));
  void _openPlaylist(String id) =>
      _navigate(() => _navigation.openDetail(DetailDestination.playlist, id));
  void _openSearch(AppDestination origin) =>
      _navigate(() => _navigation.openSearch(origin));
  void _backFromDetail() => setState(_navigation.closeDetail);

  bool _handleSystemBack() {
    if (_settingsOpen) {
      _closeSettings();
      return true;
    }
    final player = AppScope.playerOf(context);
    if (player.isExpanded) {
      player.setExpanded(false);
      return true;
    }
    if (_navigation.hasDetail) {
      _backFromDetail();
      return true;
    }
    final destination = _navigation.backDestination;
    if (destination != null) {
      _go(destination);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.appOf(context);

    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final connectionErrorValue = appState.connectionError;
        if (connectionErrorValue != null) {
          return _ConnectionScreen(
            message: connectionErrorValue,
            onRetry: appState.validateConnection,
            onLogout: appState.logout,
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            final handled = _handleSystemBack();
            if (!handled) SystemNavigator.pop();
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final navDestination = _navigation.navDestination;
              return AnimatedBuilder(
                animation: AppScope.playerOf(context),
                builder: (context, _) {
                  final player = AppScope.playerOf(context);
                  final bottomInset = MediaQuery.of(context).padding.bottom;
                  final collapsedMini = player.isMiniCollapsed;
                  final showMiniPlayer = player.hasChapter &&
                      !player.isExpanded &&
                      !hidesMiniPlayer(navDestination);
                  // 窄屏不再使用 72px 宽的纯图标侧栏：那一列在手机上放不下文字，
                  // 用户只能看到齿轮图标。改为底部标签栏，图标与文字始终同时可见，
                  // 设置作为整页打开。
                  final compactShell = constraints.maxWidth < 840;
                  if (compactShell) {
                    return _buildCompactShell(
                      context: context,
                      player: player,
                      bottomInset: bottomInset,
                      collapsedMini: collapsedMini,
                      showMiniPlayer: showMiniPlayer,
                      navDestination: navDestination,
                    );
                  }
                  final pluginExtensionBottom =
                      showMiniPlayer ? 110.0 + bottomInset : 24.0 + bottomInset;
                  return SettingsPushLayout(
                    open: _settingsOpen,
                    onOpen: _openSettings,
                    onClose: _closeSettings,
                    swipeEnabled: (_settingsOpen || !player.isExpanded) &&
                        [TargetPlatform.android, TargetPlatform.iOS]
                            .contains(Theme.of(context).platform),
                    panel: _settingsCreated
                        ? _settingsPanel()
                        : const SizedBox.shrink(),
                    child: Stack(
                      children: [
                        Scaffold(
                          body: SafeArea(
                            bottom: false,
                            child: Column(children: [
                              Row(children: [
                                if (!_settingsOpen) _homeButton(),
                                if (!_settingsOpen)
                                  IconButton(
                                    tooltip:
                                        context.localeText('设置', 'Settings'),
                                    icon: const Icon(Icons.settings_outlined),
                                    onPressed: _openSettings,
                                  ),
                                if (!appState.offlineMode &&
                                    !_navigation.hasDetail &&
                                    _primaryDestinations
                                        .contains(_destination) &&
                                    _destination != AppDestination.bookshelf)
                                  IconButton(
                                    tooltip: context.localeText('返回', 'Back'),
                                    icon: const Icon(Icons.arrow_back_rounded),
                                    onPressed: () => _go(
                                        _navigation.backDestination ??
                                            AppDestination.bookshelf),
                                  ),
                                const Spacer(),
                                if (DesktopWindow.instance.supported &&
                                    !DesktopWindow.instance.usesCustomTitleBar)
                                  IconButton(
                                    tooltip: context.localeText(
                                        '小窗模式', 'Mini window'),
                                    icon: const Icon(
                                        Icons.picture_in_picture_alt_rounded),
                                    onPressed: () =>
                                        DesktopWindow.instance.setMini(true),
                                  ),
                                const SizedBox(width: 8),
                              ]),
                              Expanded(child: _page()),
                            ]),
                          ),
                        ),
                        if (showMiniPlayer)
                          Positioned(
                            left: collapsedMini ? 24 : 12,
                            right: collapsedMini ? null : 12,
                            bottom: bottomInset + (collapsedMini ? 20 : 12),
                            child: const Material(
                              type: MaterialType.transparency,
                              child: MiniPlayer(),
                            ),
                          ),
                        if (!player.isExpanded)
                          Positioned.fill(
                            child: PluginExtensionHost(
                              bottomOffset: pluginExtensionBottom,
                              enabled: appState.pluginToolMenuEnabled &&
                                  _destination == AppDestination.plugins,
                            ),
                          ),
                        if (player.isExpanded)
                          const Positioned.fill(child: ExpandedPlayerOverlay()),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  /// 窄屏外壳：内容区加底部标签栏，设置整页打开。
  Widget _buildCompactShell({
    required BuildContext context,
    required PlayerState player,
    required double bottomInset,
    required bool collapsedMini,
    required bool showMiniPlayer,
    required AppDestination navDestination,
  }) {
    final appState = AppScope.appOf(context);
    final settingsOpen = _settingsOpen;
    final showBar = !player.isExpanded;
    final barHeight = showBar ? 58.0 + bottomInset : 0.0;
    final miniBottom = barHeight + (collapsedMini ? 20 : 12);
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 设置打开时把内容页保留在树里（Offstage），
                      // 关闭后书架、详情与滚动位置都不重来。
                      Visibility(
                        visible: !settingsOpen,
                        maintainState: true,
                        child: Column(
                          children: [
                            if (_compactBackButton(appState) case final back?)
                              back,
                            Expanded(child: _page()),
                          ],
                        ),
                      ),
                      if (settingsOpen)
                        _settingsPanel(
                          showNavigation: false,
                          // 迷你播放条浮在内容上方，给设置列表留出等高的
                          // 底部空白，滚到底时最后几项不会被压住。
                          bottomPadding: showMiniPlayer
                              ? (collapsedMini ? 88.0 : 80.0)
                              : 0.0,
                        ),
                    ],
                  ),
                ),
                // 给底部标签栏留出空间，内容不会被压住。
                SizedBox(height: barHeight),
              ],
            ),
          ),
          // 左缘右滑返回：只占最左侧 22px，避免和横向滚动、进度条拖动冲突。
          // 放在迷你播放条之前，播放条仍优先响应点击。
          if (!player.isExpanded)
            Positioned(
              left: 0,
              top: 0,
              bottom: barHeight,
              width: 22,
              child: _EdgeBackGesture(onTrigger: _handleSystemBack),
            ),
          if (showMiniPlayer)
            Positioned(
              left: collapsedMini ? 24 : 12,
              right: collapsedMini ? null : 12,
              bottom: miniBottom,
              child: const Material(
                type: MaterialType.transparency,
                child: MiniPlayer(),
              ),
            ),
          if (!player.isExpanded)
            Positioned.fill(
              child: PluginExtensionHost(
                bottomOffset:
                    showMiniPlayer ? barHeight + 110.0 : barHeight + 24.0,
                enabled: appState.pluginToolMenuEnabled &&
                    _destination == AppDestination.plugins,
              ),
            ),
          if (player.isExpanded)
            const Positioned.fill(child: ExpandedPlayerOverlay()),
          if (showBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ShellBottomBar(
                current: navDestination,
                settingsOpen: settingsOpen,
                offline: appState.offlineMode,
                onSelect: (destination) {
                  if (destination == AppDestination.mine) {
                    _openSettings();
                  } else if (settingsOpen) {
                    _closeSettings();
                    _go(destination);
                  } else {
                    _go(destination);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  /// 整页设置里选择条目：先收起设置，再进入目标页。
  void _goFromFullPageSettings(AppDestination destination) {
    if (destination == AppDestination.mine ||
        destination == AppDestination.bookshelf ||
        destination == AppDestination.downloads) {
      _closeSettings();
      _go(destination);
      return;
    }
    setState(() => _settingsOpen = false);
    _go(destination);
  }

  Widget? _compactBackButton(AppState appState) {
    if (appState.offlineMode ||
        _navigation.hasDetail ||
        !_primaryDestinations.contains(_destination) ||
        _destination == AppDestination.bookshelf) {
      return null;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 0, 0),
        child: IconButton(
          tooltip: context.localeText('返回', 'Back'),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              _go(_navigation.backDestination ?? AppDestination.bookshelf),
        ),
      ),
    );
  }

  Widget _page() {
    final app = AppScope.appOf(context);
    final identity =
        '${app.bookCacheIdentity}:${app.offlineMode}:${app.bookDetailsCache.revision}';
    if (_pageIdentity != identity) {
      _primaryPages.clear();
      _pageIdentity = identity;
    }
    if (app.offlineMode) return _buildPage();

    final primary =
        !_navigation.hasDetail && _primaryDestinations.contains(_destination);
    if (primary) _primaryPages.putIfAbsent(_destination, _buildPage);

    // 主页面首次进入时创建，切换时保留列表、滚动位置和下载选择。
    return Stack(
      key: ValueKey(identity),
      fit: StackFit.expand,
      children: [
        IndexedStack(
          index: primary ? _primaryDestinations.indexOf(_destination) : null,
          sizing: StackFit.expand,
          children: [
            for (final destination in _primaryDestinations)
              ExcludeFocus(
                excluding: !primary || _destination != destination,
                child: TickerMode(
                  enabled: primary && _destination == destination,
                  child: _primaryPages[destination] ?? const SizedBox.shrink(),
                ),
              ),
          ],
        ),
        if (!primary) _buildPage(),
      ],
    );
  }

  /// 设置侧栏里该高亮哪个入口。
  ///
  /// 收藏、历史、书单、关于等页面都归到设置这一层，否则从任一子页返回侧栏时
  /// 书架和下载都不会高亮，看不出当前所在位置。
  AppDestination _navHighlight() =>
      isMineDestination(_navigation.navDestination)
          ? AppDestination.mine
          : _navigation.navDestination;

  Widget _settingsPanel(
      {bool showNavigation = true, double bottomPadding = 0}) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 200;
      final app = AppScope.appOf(context);
      final navigation = Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 20),
        child: Column(children: [
          for (final entry in _navigationEntries(context))
            if (entry.destination != AppDestination.mine &&
                (!app.offlineMode ||
                    entry.destination == AppDestination.downloads))
              Tooltip(
                  message: entry.label,
                  child: compact
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: IconButton(
                            icon: Icon(entry.icon),
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  entry.destination == _navHighlight()
                                      ? Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer
                                      : Colors.transparent,
                            ),
                            isSelected: entry.destination == _navHighlight(),
                            onPressed: () => _go(entry.destination),
                          ))
                      : ListTile(
                          leading: Icon(entry.icon),
                          title: Text(entry.label),
                          // 主题里的选中样式只改文字颜色，在侧栏这种浅底卡片上
                          // 几乎看不出来，这里显式补一层底色和加粗。
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          selectedTileColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          selected: app.offlineMode
                              ? entry.destination == AppDestination.downloads
                              : entry.destination == _navHighlight(),
                          onTap: () => _go(entry.destination),
                        )),
        ]),
      );
      return ScaffoldMessenger(
        key: _settingsMessengerKey,
        child: Scaffold(
          body: SafeArea(
            child: Column(children: [
              if (compact) _homeButton(),
              Padding(
                padding: EdgeInsets.only(
                    left: compact ? 0 : 20, right: compact ? 0 : 8),
                child: Row(
                    mainAxisAlignment: compact
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      if (!compact) _homeButton(),
                      if (!compact)
                        Expanded(
                            child: Text(context.localeText('设置', 'Settings'),
                                style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(
                        tooltip: context.localeText('关闭设置', 'Close settings'),
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: _closeSettings,
                      ),
                    ]),
              ),
              Expanded(
                child: ListeningSettingsPage(
                  embedded: true,
                  compact: compact,
                  currentDestination: _navigation.navDestination,
                  // 窄屏外壳已经有底部标签栏，设置页里不再重复一份导航。
                  navigation: showNavigation ? navigation : null,
                  // 整页打开时，选中条目后先收起设置再进入目标页；
                  // 侧栏推入时保持设置可见，右侧切换内容。
                  go: showNavigation ? _go : _goFromFullPageSettings,
                  onOpenPluginPage: _openPluginPage,
                  pluginPages: _sidebarPluginPages,
                  activePluginPageId: _activePluginPage?.id,
                  bottomPadding: bottomPadding,
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _buildPage() {
    final bookId = _bookId;
    final playlistId = _playlistId;
    final seriesId = _seriesId;
    if (AppScope.appOf(context).offlineMode) {
      return const DownloadsPage();
    }
    if (bookId != null) {
      return BookDetailPage(
        bookId: bookId,
        initialChapterId: _bookInitialChapterId,
        onBack: _backFromDetail,
      );
    }
    if (playlistId != null) {
      return PlaylistDetailPage(
        playlistId: playlistId,
        onBack: () => _go(AppDestination.playlists),
        openBook: _openBook,
        openSeries: _openSeries,
      );
    }
    if (seriesId != null) {
      return SeriesDetailPage(
        seriesId: seriesId,
        onBack: _backFromDetail,
        openBook: _openBook,
      );
    }

    switch (_destination) {
      case AppDestination.home:
        return HomePage(
          openBook: _openBook,
          openBookshelf: () => _go(AppDestination.bookshelf),
          openHistory: () => _go(AppDestination.history),
          openSearch: () => _openSearch(AppDestination.home),
          openPlaylists: () => _go(AppDestination.playlists),
        );
      case AppDestination.bookshelf:
        return BookshelfPage(
          openBook: _openBook,
          openSeries: _openSeries,
          openLibraries: () => _go(AppDestination.libraries),
          openSearch: () => _openSearch(AppDestination.bookshelf),
        );
      case AppDestination.search:
        return SearchPage(
          openBook: _openBook,
          onBack: () => _go(_searchOrigin),
        );
      case AppDestination.favorites:
        return FavoritesPage(
          openBook: _openBook,
          openBookshelf: () => _go(AppDestination.bookshelf),
          onBack: () => _go(AppDestination.mine),
        );
      case AppDestination.mine:
        return ListeningSettingsPage(
          go: _go,
          onOpenPluginPage: _openPluginPage,
          pluginPages: _sidebarPluginPages,
          activePluginPageId: _activePluginPage?.id,
        );
      case AppDestination.windowSettings:
        return const WindowSettingsPage();
      case AppDestination.account:
        return MyPage(
          onBack: () => _go(AppDestination.mine),
          openHistory: () => _go(AppDestination.history),
          openBookmarks: () => _go(AppDestination.bookmarks),
          openFavorites: () => _go(AppDestination.favorites),
          openDownloads: () => _go(AppDestination.downloads),
          openPersonalization: () => _go(AppDestination.personalization),
          openFnConnect: () => _go(AppDestination.fnConnect),
          openNotifications: () => _go(AppDestination.notifications),
          openStatistics: () => _go(AppDestination.statistics),
          openAbout: _openAbout,
          openBook: _openBook,
        );
      case AppDestination.history:
        return HistoryPage(
          openBook: _openBookAtChapter,
          onBack: () => _go(AppDestination.mine),
          openBookshelf: () => _go(AppDestination.bookshelf),
        );
      case AppDestination.bookmarks:
        return BookmarksPage(onBack: () => _go(AppDestination.mine));
      case AppDestination.playlists:
        return PlaylistsPage(
          openPlaylist: _openPlaylist,
          onBack: () => _go(AppDestination.mine),
        );
      case AppDestination.personalization:
        return PersonalizationPage(
          openDownloads: () => _go(AppDestination.downloads),
          onBack: () => _go(AppDestination.mine),
        );
      case AppDestination.fnConnect:
        return FnConnectPage(onBack: () => _go(AppDestination.mine));
      case AppDestination.notifications:
        return NotificationSettingsPage(onBack: () => _go(AppDestination.mine));
      case AppDestination.statistics:
        return AdminStatisticsPage(onBack: () => _go(AppDestination.mine));
      case AppDestination.maintenance:
        return const ServerMaintenancePage();
      case AppDestination.downloads:
        return const DownloadsPage();
      case AppDestination.about:
        return AboutPage(
          backendVersion: _aboutBackendVersion,
          onForceRefresh: _forceRefresh,
          onBack: () => _go(AppDestination.mine),
        );
      case AppDestination.libraries:
        return const AdminLibrariesPage();
      case AppDestination.plugins:
        return PluginsPage(onViewLogs: _openPluginLogs);
      case AppDestination.logs:
        return const LogsPage();
      case AppDestination.users:
        return const AdminUsersV2Page();
      case AppDestination.pluginLogs:
        final plugin = _activePluginLogs;
        if (plugin == null) {
          return PluginsPage(onViewLogs: _openPluginLogs);
        }
        return PluginLogsPage(
          key: ValueKey(plugin.id),
          plugin: plugin,
          onBack: () => _go(AppDestination.plugins),
        );
      case AppDestination.pluginPage:
        final extension = _activePluginPage;
        if (extension == null) {
          return EmptyState(
            icon: Icons.extension_off_rounded,
            title: context.l10n.pluginPageUnavailable,
            message: context.l10n.pluginPageUnavailableDescription,
          );
        }
        final user = AppScope.appOf(context).user;
        return PluginExtensionPage(
          key: ValueKey(extension.id),
          extension: extension,
          onBack: () => _go(AppDestination.mine),
          extensionContext: <String, Object?>{
            'surface': ClientExtensionSlot.appSidebarPage.value,
            'user_id': user?.id,
            'username': user?.username,
            'role': user?.role,
          },
        );
    }
  }
}

/// 屏幕左缘的右滑返回手势。
///
/// 只在最左侧一条窄区域内响应，避免与横向列表、进度条拖动冲突；
/// 触摸到内容区后交给下层处理，不会吞掉点击。
class _EdgeBackGesture extends StatefulWidget {
  const _EdgeBackGesture({required this.onTrigger});

  final bool Function() onTrigger;

  @override
  State<_EdgeBackGesture> createState() => _EdgeBackGestureState();
}

class _EdgeBackGestureState extends State<_EdgeBackGesture> {
  double _drag = 0;
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // 手势识别器要等指针移动超过触摸阈值才算开始，那时手指已经离开屏幕
      // 左缘，所以起点必须在按下的那一刻记录，不能用 dragStart 的位置。
      onHorizontalDragDown: (details) {
        _drag = 0;
        _armed = details.localPosition.dx <= 22;
      },
      onHorizontalDragStart: (_) => _drag = 0,
      onHorizontalDragUpdate: (details) {
        if (!_armed) return;
        _drag += details.primaryDelta ?? 0;
      },
      onHorizontalDragEnd: (details) {
        if (_armed && (_drag > 48 || (details.primaryVelocity ?? 0) > 320)) {
          widget.onTrigger();
        }
        _drag = 0;
        _armed = false;
      },
      onHorizontalDragCancel: () {
        _drag = 0;
        _armed = false;
      },
      child: const SizedBox.expand(),
    );
  }
}

class _ConnectionScreen extends StatelessWidget {
  const _ConnectionScreen({
    required this.message,
    required this.onRetry,
    required this.onLogout,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ConnectionStatusCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: 72,
                      height: 72,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      context.l10n.connectionFailed,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    PrimaryButton(
                      label: context.l10n.commonRetryConnection,
                      icon: Icons.refresh_rounded,
                      onPressed: onRetry,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onLogout,
                      child: Text(context.l10n.navLogout),
                    ),
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
