import 'dart:convert';

import 'account_document_store.dart';

class ChapterReadMarksStore {
  ChapterReadMarksStore({AccountDocumentStore? documents})
      : _documents = documents ?? AccountDocumentStore();

  final AccountDocumentStore _documents;

  String _key(String identity) =>
      'chapter_read_marks:${base64Url.encode(utf8.encode(identity))}';

  Future<Set<String>> read(String identity) async {
    final raw = await _documents.read(_key(identity));
    if (raw == null) return <String>{};
    try {
      final value = jsonDecode(raw);
      if (value is! List) return <String>{};
      return value.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> write(String identity, Set<String> chapterIds) async {
    final sorted = chapterIds.toList()..sort();
    await _documents.write(_key(identity), jsonEncode(sorted));
  }
}
