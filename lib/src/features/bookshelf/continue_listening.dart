import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/models/models.dart';
import '../../core/state/books_state.dart';
import '../../core/utils/locale.dart';
import '../../shared/app_scope.dart';

class ContinueListening extends StatefulWidget {
  const ContinueListening({super.key, required this.openBook});

  final ValueChanged<String> openBook;

  @override
  State<ContinueListening> createState() => _ContinueListeningState();
}

class _ContinueListeningState extends State<ContinueListening> {
  ProgressItem? _recent;
  bool _requested = false;
  bool _starting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final response =
          await AppScope.appOf(context).api.get('/api/progress/recent');
      final items = asMapList(response.data)
          .map(ProgressItem.fromJson)
          .where((item) => item.bookId.isNotEmpty)
          .toList();
      items.sort(
        (a, b) => (DateTime.tryParse(b.updatedAt ?? '') ?? DateTime(1970))
            .compareTo(DateTime.tryParse(a.updatedAt ?? '') ?? DateTime(1970)),
      );
      if (mounted) setState(() => _recent = items.firstOrNull);
    } catch (_) {
      // 继续收听加载失败时仍然允许浏览书架。
    }
  }

  Future<void> _resume() async {
    final recent = _recent;
    if (_starting || recent == null) return;
    setState(() => _starting = true);
    final app = AppScope.appOf(context);
    final player = AppScope.playerOf(context);
    final catalogue = ChapterCatalogue(app.api, recent.bookId);
    try {
      if (player.currentBook?.id == recent.bookId && player.hasChapter) {
        if (!player.isPlaying) await player.togglePlay();
        if (mounted) player.setExpanded(true);
        return;
      }
      final response = await app.api.get(
        '/api/books/${Uri.encodeComponent(recent.bookId)}',
      );
      final chapters = await catalogue.all();
      if (!mounted) return;
      if (chapters == null || chapters.isEmpty) {
        widget.openBook(recent.bookId);
        return;
      }
      final chapter =
          chapters.where((item) => item.id == recent.chapterId).firstOrNull;
      await player.playChapter(
        Book.fromJson(asMap(response.data)),
        chapters,
        chapter ?? chapters.first,
        startAt: chapter == null ? null : recent.position,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiError.messageFor(error))));
      }
    } finally {
      catalogue.dispose();
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recent = _recent;
    if (recent == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.primaryContainer,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => widget.openBook(recent.bookId),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.localeText('继续收听', 'Continue listening'),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        recent.bookTitle ??
                            context.localeText('最近收听', 'Recently played'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (recent.chapterTitle?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          recent.chapterTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              IconButton.filled(
                tooltip: context.localeText('继续播放', 'Resume playback'),
                onPressed: _starting ? null : _resume,
                icon: _starting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                iconSize: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
