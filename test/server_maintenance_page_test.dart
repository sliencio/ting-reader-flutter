import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ting_reader_flutter/l10n/app_localizations.dart';
import 'package:ting_reader_flutter/src/core/api/api_client.dart';
import 'package:ting_reader_flutter/src/core/models/models.dart';
import 'package:ting_reader_flutter/src/core/state/app_state.dart';
import 'package:ting_reader_flutter/src/core/state/download_state.dart';
import 'package:ting_reader_flutter/src/core/state/player_state.dart';
import 'package:ting_reader_flutter/src/features/mine/server_maintenance_page.dart';
import 'package:ting_reader_flutter/src/shared/app_scope.dart';

class _Api extends ApiClient {
  final reads = <String>[];
  final writes = <String>[];
  bool pending = false;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? params, CancelToken? cancelToken}) async {
    reads.add(path);
    return Response(
        requestOptions: RequestOptions(path: path),
        data: switch (path) {
          '/api/system/maintenance' => {
              'automatic_backup': true,
              'backup_interval_hours': 24,
              'backup_retention': 7,
              'preload_window_mib': 4,
              'preload_memory_mib': 32,
              'preload_idle_seconds': 60,
              'disk_cache_chapters': 50,
              'disk_cache_mib': null,
            },
          '/api/system/backups' => {
              'pending_restore': pending,
              'files': [
                {
                  'name': 'manual-20261030-test.db',
                  'bytes': 1024,
                  'created_at': '2026-10-30T00:00:00Z'
                }
              ]
            },
          _ => <dynamic>[],
        });
  }

  @override
  Future<Response<dynamic>> post(String path,
      {Object? data,
      Map<String, dynamic>? params,
      CancelToken? cancelToken,
      Duration? receiveTimeout}) async {
    writes.add(path);
    expect(data, {'confirmation': '恢复备份'});
    pending = true;
    return Response(
        requestOptions: RequestOptions(path: path),
        data: {'requires_restart': true});
  }
}

class _App extends AppState {
  final fixture = _Api();
  @override
  ApiClient get api => fixture;
}

class _Player extends ChangeNotifier implements PlayerState {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_App> _show(WidgetTester tester, Size size, {bool admin = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final app = _App()
    ..user =
        User(id: 'user', username: 'reader', role: admin ? 'admin' : 'user');
  final player = _Player();
  final downloads = DownloadState(app);
  addTearDown(app.dispose);
  addTearDown(player.dispose);
  addTearDown(downloads.dispose);
  await tester.pumpWidget(AppScope(
      appState: app,
      downloadState: downloads,
      playerState: player,
      child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ServerMaintenancePage()))));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('维护页面在 $size 下确认恢复后仅暂存，键盘可以收起', (tester) async {
      final app = await _show(tester, size);
      final restore = find.text('恢复');
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(app.fixture.writes, isEmpty);
      final field = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(field, '恢复');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '确认暂存'))
              .onPressed,
          isNull);
      await tester.enterText(field, '恢复备份');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      final confirm = find.text('确认暂存');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(app.fixture.writes,
          ['/api/system/backups/manual-20261030-test.db/restore']);
      expect(app.fixture.pending, isTrue);
      expect(find.text('取消待恢复请求'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('取消恢复不发送写入请求', (tester) async {
    final app = await _show(tester, const Size(390, 844));
    await tester.ensureVisible(find.text('恢复'));
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(app.fixture.writes, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('普通账号不读取管理员维护接口', (tester) async {
    final app = await _show(tester, const Size(390, 844), admin: false);
    expect(find.text('仅管理员可管理服务端'), findsOneWidget);
    expect(app.fixture.reads, isEmpty);
    expect(app.fixture.writes, isEmpty);
  });
}
