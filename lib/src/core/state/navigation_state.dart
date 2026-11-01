import '../models/models.dart';
import '../plugin_extensions/types.dart';

enum AppDestination {
  home,
  bookshelf,
  search,
  favorites,
  mine,
  windowSettings,
  account,
  history,
  bookmarks,
  playlists,
  personalization,
  fnConnect,
  notifications,
  statistics,
  maintenance,
  downloads,
  about,
  libraries,
  plugins,
  logs,
  users,
  pluginLogs,
  pluginPage,
}

enum DetailDestination { book, series, playlist }

/// Shell routing rules. A detail route has exactly one kind and identifier,
/// so opening a book cannot leave a series or playlist route active.
class ShellNavigation {
  ShellNavigation();

  factory ShellNavigation.fromQuery(Map<String, String> query) {
    final state = ShellNavigation();
    state.destination = switch (query['page']) {
      'settings' => AppDestination.personalization,
      'fn-connect' => AppDestination.fnConnect,
      'plugin-page' => AppDestination.pluginPage,
      final name =>
        AppDestination.values.where((item) => item.name == name).firstOrNull ??
            AppDestination.bookshelf,
    };
    state.initialPluginId = query['plugin'];
    state.initialCapabilityId = query['capability'];
    final book = query['book'];
    final series = query['series'];
    final playlist = query['playlist'];
    if (book != null && book.isNotEmpty) {
      state.openDetail(DetailDestination.book, book, chapter: query['chapter']);
    } else if (series != null && series.isNotEmpty) {
      state.openDetail(DetailDestination.series, series);
    } else if (playlist != null && playlist.isNotEmpty) {
      state.openDetail(DetailDestination.playlist, playlist);
    }
    return state;
  }

  AppDestination destination = AppDestination.bookshelf;
  AppDestination searchOrigin = AppDestination.bookshelf;
  ({DetailDestination kind, String id, String? chapter})? _detail;
  String? aboutBackendVersion;
  ClientExtensionDescriptor? activePluginPage;
  PluginItem? activePluginLogs;
  String? initialPluginId;
  String? initialCapabilityId;

  String? get bookId =>
      _detail?.kind == DetailDestination.book ? _detail?.id : null;
  String? get chapterId =>
      _detail?.kind == DetailDestination.book ? _detail?.chapter : null;
  String? get seriesId =>
      _detail?.kind == DetailDestination.series ? _detail?.id : null;
  String? get playlistId =>
      _detail?.kind == DetailDestination.playlist ? _detail?.id : null;
  bool get hasDetail => _detail != null;

  void go(AppDestination next) {
    destination = next;
    _detail = null;
    aboutBackendVersion = null;
    activePluginPage = null;
    activePluginLogs = null;
  }

  void openDetail(DetailDestination kind, String id, {String? chapter}) {
    _detail = (
      kind: kind,
      id: id,
      chapter: kind == DetailDestination.book ? chapter : null,
    );
    activePluginPage = null;
    activePluginLogs = null;
  }

  void closeDetail() => _detail = null;

  void openPluginPage(ClientExtensionDescriptor extension) {
    go(AppDestination.pluginPage);
    activePluginPage = extension;
  }

  void openPluginLogs(PluginItem plugin) {
    go(AppDestination.pluginLogs);
    activePluginLogs = plugin;
  }

  void openAbout(String? version) {
    go(AppDestination.about);
    aboutBackendVersion = version;
  }

  void openSearch(AppDestination origin) {
    searchOrigin = origin;
    go(AppDestination.search);
  }

  AppDestination? get backDestination => switch (destination) {
        AppDestination.bookshelf => null,
        AppDestination.pluginLogs => AppDestination.plugins,
        AppDestination.search => searchOrigin,
        AppDestination.account ||
        AppDestination.windowSettings ||
        AppDestination.playlists ||
        AppDestination.favorites ||
        AppDestination.history ||
        AppDestination.bookmarks ||
        AppDestination.personalization ||
        AppDestination.fnConnect ||
        AppDestination.notifications ||
        AppDestination.statistics ||
        AppDestination.maintenance ||
        AppDestination.about =>
          AppDestination.mine,
        _ => AppDestination.bookshelf,
      };

  AppDestination get navDestination => switch (_detail?.kind) {
        DetailDestination.book ||
        DetailDestination.series =>
          AppDestination.bookshelf,
        DetailDestination.playlist => AppDestination.playlists,
        null => destination == AppDestination.pluginLogs
            ? AppDestination.plugins
            : destination,
      };
}

/// 把任意页面归到它所属的顶层标签。
///
/// 底部标签栏和左侧设置导航都只显示三个入口，但可进入的页面有二十多个
/// （收藏、历史、书单、关于、服务端管理…）。只按「目标页 === 标签页」
/// 判断高亮时，这些子页面会让所有标签同时熄灭，用户看不出自己在哪。
/// 统一在这里做归属映射，两处导航共用同一套规则。
AppDestination rootTabFor(AppDestination destination) => switch (destination) {
      AppDestination.bookshelf ||
      AppDestination.search ||
      AppDestination.home =>
        AppDestination.bookshelf,
      AppDestination.downloads => AppDestination.downloads,
      _ => AppDestination.mine,
    };

bool isMineDestination(AppDestination destination) => switch (destination) {
      AppDestination.mine ||
      AppDestination.windowSettings ||
      AppDestination.account ||
      AppDestination.history ||
      AppDestination.bookmarks ||
      AppDestination.favorites ||
      AppDestination.personalization ||
      AppDestination.fnConnect ||
      AppDestination.notifications ||
      AppDestination.statistics ||
      AppDestination.maintenance ||
      AppDestination.downloads ||
      AppDestination.about =>
        true,
      _ => false,
    };

bool hidesMiniPlayer(AppDestination destination) => switch (destination) {
      AppDestination.windowSettings ||
      AppDestination.personalization ||
      AppDestination.fnConnect ||
      AppDestination.notifications ||
      AppDestination.statistics ||
      AppDestination.maintenance ||
      AppDestination.about ||
      AppDestination.libraries ||
      AppDestination.plugins ||
      AppDestination.logs ||
      AppDestination.users ||
      AppDestination.pluginLogs ||
      AppDestination.pluginPage =>
        true,
      _ => false,
    };
