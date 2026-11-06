part of '../mini_player.dart';

class _ExpandedPlayer extends StatefulWidget {
  const _ExpandedPlayer({super.key, required this.player});

  final PlayerState player;

  @override
  State<_ExpandedPlayer> createState() => _ExpandedPlayerState();
}

class _ExpandedPlayerState extends State<_ExpandedPlayer> {
  int? get _sleepRemainingSeconds => widget.player.sleepRemainingSeconds;
  // 按集数睡眠的状态由 PlayerState 管理（避免 widget 销毁丢失）。
  CoverShape _coverShape = CoverShape.square;
  double? _dragSeekValue;

  void _updateMenuState(VoidCallback change) => setState(change);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _coverShape = coverShapeFromAppSettings(AppScope.appOf(context).settings);
  }

  Future<void> _openChapterSheet(
    BuildContext context,
    PlayerState player,
    Color? themeColor,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) =>
          _ChapterSheetList(player: player, themeColor: themeColor),
    );
  }

  String _formatSleepTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  /// 封面只是「理想尺寸」。竖屏手机上按视口高度留出控制区的空间，
  /// 让常规尺寸的屏幕不必再触发整体缩放；真正放不下时由布局层兜底。
  Size _expandedCoverBounds({
    required bool tightControls,
    required Size viewport,
  }) {
    final portraitPhone =
        viewport.height > viewport.width && viewport.width < 600;
    final squareMaxSize = tightControls ? 300.0 : 340.0;
    final baseMaxWidth = _coverShape == CoverShape.square
        ? squareMaxSize
        : (tightControls ? 280.0 : 320.0);
    var baseMaxHeight = _coverShape == CoverShape.square
        ? squareMaxSize
        : (tightControls ? 340.0 : 390.0);
    if (portraitPhone) {
      // 控制区（标题、快捷按钮、进度条、播放键）大约占 470 逻辑像素。
      final minHeight = _coverShape == CoverShape.square ? 132.0 : 156.0;
      baseMaxHeight =
          (viewport.height - 470).clamp(minHeight, baseMaxHeight).toDouble();
    }
    return Size(baseMaxWidth, baseMaxHeight);
  }

  double _expandedBottomContentPadding({
    required Size screenSize,
    required EdgeInsets safePadding,
  }) {
    final portraitPhone =
        screenSize.height > screenSize.width && screenSize.width < 600;
    if (!portraitPhone) return 28.0;

    const referencePortraitHeight = 900.0;
    const referenceBottomPadding = 28.0;
    final heightRatio = (screenSize.height / referencePortraitHeight).clamp(
      0.0,
      1.0,
    );
    final scaledPadding = (referenceBottomPadding * heightRatio)
        .clamp(12.0, referenceBottomPadding)
        .toDouble();
    final safeAreaAdjustment = safePadding.bottom * 0.65;
    return (scaledPadding - safeAreaAdjustment)
        .clamp(8.0, referenceBottomPadding)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.appOf(context);
    final mediaPadding = MediaQuery.paddingOf(context);

    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return AnimatedBuilder(
        animation: widget.player,
        builder: (context, _) {
          final player = widget.player;
          final remaining = _sleepRemainingSeconds;
          final book = player.currentBook;
          final chapter = player.currentChapter;
          if (book == null || chapter == null) return const SizedBox.shrink();
          final downloadAction = _downloadActionFor(chapter);
          final maxDuration = player.duration > 0
              ? player.duration
              : chapter.duration.toDouble();
          final sliderMax = maxDuration <= 0 ? 1.0 : maxDuration;
          final sliderValue = (_dragSeekValue ?? player.currentTime)
              .clamp(0, sliderMax)
              .toDouble();
          final themeColor = effectiveBookThemeColor(book.themeColor);
          final accentColor = themeColor ?? AppColors.primary600;
          final accentTextColor =
              themeColor != null && isBookThemeLight(themeColor)
                  ? AppColors.slate600
                  : Colors.white;
          final coverUrl = bookCoverUrl(appState, book);
          final backgroundColor = context.isDark
              ? AppColors.slate950
              : Color.alphaBlend(
                  (themeColor ?? AppColors.primary600).withValues(alpha: 0.08),
                  const Color(0xfffbfaf7),
                );
          final compactControls = size.width < 480 || size.height < 760;
          final tightControls = size.width < 380 || size.height < 680;
          final mainButtonSize =
              tightControls ? 66.0 : (compactControls ? 74.0 : 80.0);
          final mainIconSize =
              tightControls ? 32.0 : (compactControls ? 36.0 : 38.0);
          final sideButtonSize =
              tightControls ? 42.0 : (compactControls ? 46.0 : 50.0);
          final sideIconSize =
              tightControls ? 22.0 : (compactControls ? 24.0 : 26.0);
          final controlGap =
              tightControls ? 14.0 : (compactControls ? 18.0 : 22.0);
          final bottomContentPadding = _expandedBottomContentPadding(
            screenSize: size,
            safePadding: mediaPadding,
          );
          final coverBounds = _expandedCoverBounds(
            tightControls: tightControls,
            viewport: size,
          );
          final header = Row(
            children: [
              _IconCircle(
                icon: Icons.keyboard_arrow_down_rounded,
                ghost: true,
                onPressed: () async => player.setExpanded(false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                  ),
                  // 章节标题已在控制区以大字号展示，这里只保留书名，避免重复。
                  child: Text(
                    localizedBookTitle(context, book),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.mutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: context.localeText('更多', 'More'),
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (value) {
                  switch (value) {
                    case 'bookmarks':
                      _openBookmarks(player);
                      break;
                    case 'download':
                      _downloadCurrentChapter(player);
                      break;
                    case 'settings':
                      _openPlaybackSettings(player, book);
                      break;
                    case 'positions':
                      showListeningCheckpoints(context, player);
                      break;
                    case 'sync':
                      showListeningSync(context, player);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                      value: 'positions',
                      child:
                          Text(context.localeText('进度找回', 'Restore position'))),
                  PopupMenuItem(
                      value: 'sync',
                      child: Text(context.localeText('进度同步', 'Progress sync'))),
                  PopupMenuItem(
                    value: 'bookmarks',
                    child: Text(
                      context.localeText('书签', 'Bookmarks'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'download',
                    child: Text(downloadAction.label),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    child: Text(
                      context.localeText(
                        '播放设置',
                        'Playback settings',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
          final cover = ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: coverBounds.width,
              maxHeight: coverBounds.height,
            ),
            child: AspectRatio(
              aspectRatio: coverAspectRatio(_coverShape),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: context.isDark ? AppColors.slate800 : Colors.white,
                    width: 7,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: context.isDark ? 0.44 : 0.18,
                      ),
                      blurRadius: 34,
                      offset: const Offset(0, 22),
                    ),
                  ],
                ),
                child: CoverImage(url: coverUrl, radius: 24),
              ),
            ),
          );
          final controls = Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: MediaQuery.textScalerOf(context)
                          .scale(tightControls ? 22 : 24) *
                      1.18 +
                  6,
              child: ScrollingText(
                text: localizedChapterTitle(context, chapter),
                style: TextStyle(
                  fontSize: tightControls ? 22 : 24,
                  height: 1.18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              book.narrator ?? book.author ?? localizedBookTitle(context, book),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.tertiaryText,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
            ),
            PlaybackStatusNotice(player: player),
            SizedBox(height: tightControls ? 16 : 20),
            Row(
              children: [
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.bolt_rounded,
                    label: _formatPlaybackSpeed(
                      player.playbackSpeed,
                    ),
                    active: player.playbackSpeed != 1,
                    onTapWithContext: (buttonContext) =>
                        _openSpeedSheet(player, buttonContext),
                  ),
                ),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.timer_outlined,
                    label: remaining != null
                        ? _formatSleepTime(remaining)
                        : player.sleepEpisodesRemaining != null
                            ? context.localeText(
                                '${player.sleepEpisodesRemaining} 集',
                                '${player.sleepEpisodesRemaining} ep',
                              )
                            : context.localeText('定时', 'Timer'),
                    active: remaining != null ||
                        player.sleepEpisodesRemaining != null,
                    onTapWithContext: (buttonContext) => _openSleepTimerSheet(
                      player,
                      buttonContext,
                    ),
                  ),
                ),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.list_alt_rounded,
                    label: context.localeText('选集', 'Chapters'),
                    onTap: () => _openChapterSheet(
                      context,
                      player,
                      themeColor,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: tightControls ? 14 : 20),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                activeTrackColor: accentColor,
                inactiveTrackColor:
                    context.isDark ? AppColors.slate800 : AppColors.slate200,
                thumbColor: Colors.white,
                overlayColor: accentColor.withValues(alpha: 0.14),
                thumbShape: _GlowSliderThumb(color: accentColor),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                min: 0,
                max: sliderMax,
                value: sliderValue,
                onChanged: (value) => setState(() => _dragSeekValue = value),
                onChangeStart: (_) =>
                    setState(() => _dragSeekValue = sliderValue),
                onChangeEnd: (value) {
                  setState(() => _dragSeekValue = null);
                  player.seek(value);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  _SeekButton(
                    icon: Icons.rotate_left_rounded,
                    label: '15',
                    onPressed: () => player.seek(
                      (player.currentTime - 15)
                          .clamp(0, maxDuration)
                          .toDouble(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formatDurationShort(sliderValue),
                    style: TextStyle(
                      color: context.secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatDurationShort(maxDuration),
                    style: TextStyle(
                      color: context.tertiaryText,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _SeekButton(
                    icon: Icons.rotate_right_rounded,
                    label: '15',
                    onPressed: () => player.seek(
                      (player.currentTime + 15)
                          .clamp(0, maxDuration)
                          .toDouble(),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: tightControls ? 20 : 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _IconCircle(
                  icon: Icons.skip_previous_rounded,
                  onPressed: player.previousChapter,
                  diameter: sideButtonSize,
                  iconSize: sideIconSize,
                ),
                SizedBox(width: controlGap),
                _IconCircle(
                  filled: true,
                  icon: player.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onPressed: player.togglePlay,
                  loading: player.isLoading,
                  diameter: mainButtonSize,
                  iconSize: mainIconSize,
                  fillColor: accentColor,
                  filledIconColor: accentTextColor,
                ),
                SizedBox(width: controlGap),
                _IconCircle(
                  icon: Icons.skip_next_rounded,
                  onPressed: player.nextChapter,
                  diameter: sideButtonSize,
                  iconSize: sideIconSize,
                ),
              ],
            ),
          ]);
          return Material(
            color: backgroundColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: backgroundColor),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: context.isDark ? 0.24 : 0.18,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                        child: Transform.scale(
                          scale: 1.18,
                          child: CoverImage(
                            url: coverUrl,
                            radius: 0,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: context.isDark
                            ? [
                                AppColors.slate950.withValues(alpha: 0.92),
                                AppColors.slate950.withValues(alpha: 0.86),
                                AppColors.slate950.withValues(alpha: 0.96),
                              ]
                            : [
                                backgroundColor.withValues(alpha: 0.90),
                                backgroundColor.withValues(alpha: 0.72),
                                backgroundColor.withValues(alpha: 0.94),
                              ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: _ExpandedPlayerLayout(
                    header: header,
                    cover: cover,
                    controls: controls,
                    bottomPadding: bottomContentPadding,
                    coverGap: tightControls ? 20 : 24,
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}

class _ExpandedPlayerLayout extends StatelessWidget {
  const _ExpandedPlayerLayout({
    required this.header,
    required this.cover,
    required this.controls,
    required this.bottomPadding,
    required this.coverGap,
  });

  final Widget header;
  final Widget cover;
  final Widget controls;
  final double bottomPadding;
  final double coverGap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final desktop = [
            TargetPlatform.windows,
            TargetPlatform.macOS,
            TargetPlatform.linux,
          ].contains(Theme.of(context).platform);
          // 按播放区域实际宽度分栏，侧栏展开和窗口缩放后也重新适配。
          final sideBySide = desktop && constraints.maxWidth >= 700;
          final padding = EdgeInsets.fromLTRB(22, 18, 22, bottomPadding);
          final limit = sideBySide ? 1040.0 : 560.0;
          final availableWidth =
              (constraints.maxWidth - padding.horizontal).clamp(0.0, limit);
          // 详情页不滚动：内容先按自然高度排一遍，放不下时整体等比缩小，
          // 这样进度冲突、错误提示、系统大字体都不会把播放按钮顶出屏幕。
          return Padding(
            padding: padding,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: SizedBox(
                  width: availableWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      header,
                      const SizedBox(height: 28),
                      if (sideBySide)
                        Row(children: [
                          Expanded(flex: 4, child: Center(child: cover)),
                          const SizedBox(width: 32),
                          Expanded(flex: 5, child: controls),
                        ])
                      else ...[
                        cover,
                        SizedBox(height: coverGap),
                        controls,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}
