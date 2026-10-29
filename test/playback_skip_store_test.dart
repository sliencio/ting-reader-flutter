import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ting_reader_flutter/src/core/services/playback_skip_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('片头片尾在重新创建存储后保留，并按服务器账号和书籍隔离', () async {
    final store = PlaybackSkipStore();
    await store.write(
        'server:user', 'book', const PlaybackSkipSettings(30, 15));
    final restored = PlaybackSkipStore();
    final settings = await restored.read('server:user', 'book');
    expect(settings?.intro, 30);
    expect(settings?.outro, 15);
    expect(await restored.read('server:other-user', 'book'), isNull);
    expect(await restored.read('other-server:user', 'book'), isNull);
    expect(await restored.read('server:user', 'other-book'), isNull);
  });

  test('零秒作为显式关闭设置保存，负数不能覆盖已有设置', () async {
    final store = PlaybackSkipStore();
    expect(await store.read('user', 'book'), isNull);
    await store.write('user', 'book', const PlaybackSkipSettings(0, 0));
    await expectLater(
        store.write('user', 'book', const PlaybackSkipSettings(-1, 20)),
        throwsArgumentError);
    final restored = await PlaybackSkipStore().read('user', 'book');
    expect(restored?.intro, 0);
    expect(restored?.outro, 0);
  });
}
