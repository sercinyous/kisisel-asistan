import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/avatar/avatar_spec.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ritim_avatar.dart';
import '../../../core/widgets/ritim_ui.dart';
import '../../../core/widgets/sunset_stripe.dart';
import '../data/stories_repository.dart';
import '../domain/story_models.dart';
import 'stories_providers.dart';

/// Tam ekran story görüntüleyici: dokun ilerle (sol üçte bir geri), basılı
/// tut duraklat, aşağı kaydır kapat; üstte ilerleme çubukları. Hareket
/// azaltma açıksa kartlar kendiliğinden ilerlemez ve geçiş animasyonu yoktur.
class StoryViewer extends ConsumerStatefulWidget {
  const StoryViewer({super.key, required this.groups, this.initial = 0});

  final List<StoryGroup> groups;
  final int initial;

  static const Duration slideDuration = Duration(seconds: 5);

  static Future<void> open(
    BuildContext context, {
    required List<StoryGroup> groups,
    int initial = 0,
  }) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        fullscreenDialog: true,
        transitionDuration:
            reduce ? Duration.zero : const Duration(milliseconds: 220),
        reverseTransitionDuration:
            reduce ? Duration.zero : const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => StoryViewer(groups: groups, initial: initial),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  ConsumerState<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends ConsumerState<StoryViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  late int _group;
  int _slide = 0;
  double _drag = 0;
  bool _paused = false;
  bool _reduceMotion = false;
  bool _started = false;

  /// Bu görüntülemede verilen tepkiler (story kimliği → emoji).
  final Map<String, String?> _reactions = {};

  StoryGroup get _current => widget.groups[_group];

  @override
  void initState() {
    super.initState();
    _group = widget.initial.clamp(0, widget.groups.length - 1);
    _progress = AnimationController(vsync: this, duration: StoryViewer.slideDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && !_reduceMotion) _next();
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_started) {
      _started = true;
      _startSlide();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _startSlide() {
    final key = _current.seenKeys[_slide];
    // Sağlayıcı build sırasında değiştirilmesin diye kare sonrasına ertelenir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(storySeenProvider.notifier).markSeen([key]);
    });
    if (_reduceMotion) {
      _progress.value = 1;
      _progress.stop();
    } else {
      _progress.forward(from: 0);
      if (_paused) _progress.stop();
    }
  }

  void _close() {
    if (_reactions.isNotEmpty) ref.invalidate(friendStoryGroupsProvider);
    Navigator.of(context).maybePop();
  }

  void _next() {
    if (_slide < _current.slides.length - 1) {
      setState(() => _slide++);
    } else if (_group < widget.groups.length - 1) {
      setState(() {
        _group++;
        _slide = 0;
      });
    } else {
      _close();
      return;
    }
    _startSlide();
  }

  void _previous() {
    if (_slide > 0) {
      setState(() => _slide--);
    } else if (_group > 0) {
      setState(() {
        _group--;
        _slide = widget.groups[_group].slides.length - 1;
      });
    } else {
      _startSlide();
      return;
    }
    _startSlide();
  }

  void _setPaused(bool paused) {
    if (_reduceMotion) return;
    setState(() => _paused = paused);
    if (paused) {
      _progress.stop();
    } else if (_progress.value < 1) {
      _progress.forward();
    }
  }

  Future<void> _react(FriendStory story, String emoji) async {
    final repo = ref.read(storiesRepositoryProvider);
    final before = _reactions.containsKey(story.id)
        ? _reactions[story.id]
        : story.reactionOf(repo.currentUserId);
    final next = before == emoji ? null : emoji;
    setState(() => _reactions[story.id] = next);
    try {
      await repo.react(story.id, next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _reactions[story.id] = before);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Tepki gönderilemedi. Tekrar dene.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _current;
    final slide = group.slides[_slide];
    final story = group.kind == StoryKind.friend && _slide < group.stories.length
        ? group.stories[_slide]
        : null;
    final repo = ref.watch(storiesRepositoryProvider);
    final myReaction = story == null
        ? null
        : _reactions.containsKey(story.id)
            ? _reactions[story.id]
            : story.reactionOf(repo.currentUserId);

    return Scaffold(
      key: const ValueKey('story-viewer'),
      backgroundColor: AppColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final width = MediaQuery.sizeOf(context).width;
          if (d.localPosition.dx < width / 3) {
            _previous();
          } else {
            _next();
          }
        },
        onLongPressStart: (_) => _setPaused(true),
        onLongPressEnd: (_) => _setPaused(false),
        onVerticalDragUpdate: (d) =>
            setState(() => _drag = (_drag + d.delta.dy).clamp(0, 400)),
        onVerticalDragEnd: (d) {
          if (_drag > 120 || (d.primaryVelocity ?? 0) > 700) {
            _close();
          } else {
            setState(() => _drag = 0);
          }
        },
        child: Transform.translate(
          offset: Offset(0, _drag),
          child: DecoratedBox(
            key: ValueKey('story-slide-${group.id}-${slide.id}'),
            decoration: BoxDecoration(gradient: _background(slide.tone)),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.sm,
                  AppSpacing.page,
                  AppSpacing.l,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProgressBars(
                      count: group.slides.length,
                      index: _slide,
                      progress: _progress,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Header(group: group, onClose: _close, paused: _paused),
                    const Spacer(),
                    _SlideBody(slide: slide),
                    const Spacer(),
                    if (story != null)
                      _Reactions(
                        selected: myReaction,
                        onReact: (e) => _react(story, e),
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

  /// Vice City esintisi: gece moru → zemin → gün batımı, kartın tonuyla.
  LinearGradient _background(StoryTone tone) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.nightPurple.withValues(alpha: 0.85),
          AppColors.background,
          storyToneColor(tone).withValues(alpha: 0.28),
          AppColors.sunsetEnd.withValues(alpha: 0.32),
        ],
        stops: const [0, 0.45, 0.8, 1],
      );
}

/// Kart tonunun renk rolü.
Color storyToneColor(StoryTone tone) => switch (tone) {
      StoryTone.mint => AppColors.accent,
      StoryTone.peach => AppColors.fitness,
      StoryTone.lav => AppColors.sleep,
      StoryTone.sky => AppColors.water,
      StoryTone.butter => AppColors.sunsetStart,
      StoryTone.rose => AppColors.danger,
    };

class _ProgressBars extends StatelessWidget {
  const _ProgressBars({
    required this.count,
    required this.index,
    required this.progress,
  });

  final int count;
  final int index;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kart ${index + 1} / $count',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AnimatedBuilder(
                  animation: progress,
                  builder: (_, __) => RitimStatBar(
                    key: ValueKey('story-progress-$i'),
                    height: 3,
                    color: AppColors.textPrimary,
                    value: i < index
                        ? 1
                        : i == index
                            ? progress.value
                            : 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.group, required this.onClose, required this.paused});

  final StoryGroup group;
  final VoidCallback onClose;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final Widget face = switch (group.kind) {
      StoryKind.friend => RitimAvatar(
          choice: group.avatar ?? const AvatarChoice(),
          name: group.label,
          userId: group.friendId,
          size: 32,
        ),
      StoryKind.daily => Icon(Icons.wb_sunny_outlined, color: AppColors.sunsetMid),
      StoryKind.tips => Icon(Icons.lightbulb_outline_rounded, color: AppColors.accent),
    };
    return Row(
      children: [
        face,
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            group.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.value,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (paused) RitimBadge('Duraklatıldı', color: AppColors.textSecondary),
        IconButton(
          key: const ValueKey('story-close'),
          tooltip: 'Kapat',
          onPressed: onClose,
          icon: Icon(Icons.close_rounded, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

class _SlideBody extends StatelessWidget {
  const _SlideBody({required this.slide});

  final StorySlide slide;

  @override
  Widget build(BuildContext context) {
    final tone = storyToneColor(slide.tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SunsetStripe(width: 56),
        const SizedBox(height: AppSpacing.md),
        Text(
          slide.eyebrow,
          style: TextStyle(
            fontSize: AppType.caption,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: tone,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          slide.title,
          style: TextStyle(
            fontSize: 28,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        if (slide.value != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            slide.value!,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
        if (slide.progress != null) ...[
          const SizedBox(height: AppSpacing.md),
          RitimStatBar(value: slide.progress!, color: tone, height: 8),
        ],
        if (slide.body != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            slide.body!,
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _Reactions extends StatelessWidget {
  const _Reactions({required this.selected, required this.onReact});

  final String? selected;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final e in storyReactionEmojis)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Semantics(
              button: true,
              selected: selected == e,
              label: 'Tepki $e',
              child: GestureDetector(
                key: ValueKey('story-react-$e'),
                onTap: () => onReact(e),
                child: Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected == e ? AppColors.selection : AppColors.glass,
                    border: Border.all(
                      color: selected == e ? AppColors.sunsetMid : AppColors.glassBorder,
                    ),
                  ),
                  child: ExcludeSemantics(
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
