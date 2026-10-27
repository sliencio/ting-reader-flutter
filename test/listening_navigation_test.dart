import 'package:flutter_test/flutter_test.dart';
import 'package:ting_reader_flutter/src/core/state/navigation_state.dart';

void main() {
  test('launch and unknown links open the bookshelf', () {
    expect(ShellNavigation.fromQuery({}).destination, AppDestination.bookshelf);
    expect(
      ShellNavigation.fromQuery({'page': 'unknown'}).destination,
      AppDestination.bookshelf,
    );
    expect(ShellNavigation().backDestination, isNull);
  });

  test(
    'secondary settings pages return to settings and downloads return to shelf',
    () {
      final navigation = ShellNavigation();
      for (final destination in [
        AppDestination.account,
        AppDestination.personalization,
        AppDestination.playlists,
        AppDestination.history,
        AppDestination.about,
      ]) {
        navigation.go(destination);
        expect(navigation.backDestination, AppDestination.mine);
      }
      navigation.go(AppDestination.downloads);
      expect(navigation.backDestination, AppDestination.bookshelf);
    },
  );

  test('closing a book opened from downloads preserves its origin', () {
    final navigation = ShellNavigation()..go(AppDestination.downloads);
    navigation.openDetail(DetailDestination.book, 'book', chapter: 'chapter');
    expect(navigation.chapterId, 'chapter');
    navigation.closeDetail();
    expect(navigation.destination, AppDestination.downloads);
    expect(navigation.hasDetail, isFalse);
  });
}
