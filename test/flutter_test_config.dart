import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // Persistent book caches use preferences too. Widget tests must not wait
    // on real platform storage or inherit another test's saved bookshelf.
    SharedPreferences.setMockInitialValues({});
  });
  await testMain();
}
