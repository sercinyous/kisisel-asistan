import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

// Kokpit'in hareket dili: kademeli giriş, sayı sayma, kutlama darbesi.
// Tümü kısa (en fazla 400 ms) ve "Hareketi azalt" açıkken kapalıdır.

/// Sistem "Hareketi azalt" / animasyonları kapat ayarı açıksa `true`.
bool kokpitReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Kokpit animasyon süreleri.
abstract final class KokpitMotion {
  static const Duration entrance = Duration(milliseconds: 280);
  static const Duration stagger = Duration(milliseconds: 40);
  static const Duration fill = Duration(milliseconds: 400);
  static const Duration celebrate = Duration(milliseconds: 380);

  /// Kademeli girişte en fazla bu kadar sıra gecikir (toplam ≤ 400 ms).
  static const int maxStaggerSteps = 3;
}

/// Kartın ilk görünüşte hafifçe aşağıdan süzülerek belirmesi. [index]
/// sırası kadar gecikir; hareket azaltılmışsa doğrudan çizilir.
class KokpitEntrance extends StatefulWidget {
  const KokpitEntrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<KokpitEntrance> createState() => _KokpitEntranceState();
}

class _KokpitEntranceState extends State<KokpitEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final delay = KokpitMotion.stagger *
        math.min(widget.index, KokpitMotion.maxStaggerSteps);
    final total = KokpitMotion.entrance + delay;
    _controller = AnimationController(vsync: this, duration: total);
    final start = delay.inMicroseconds / total.inMicroseconds;
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (kokpitReduceMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ağaç şekli sabit kalır; aksi halde animasyon bitince çocuk yeniden
    // kurulur ve içindeki dolum/sayma animasyonları baştan başlar.
    return FadeTransition(
      opacity: _curve,
      child: AnimatedBuilder(
        animation: _curve,
        child: widget.child,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, (1 - _curve.value) * 14),
          child: child,
        ),
      ),
    );
  }
}

/// Tam sayıyı ilk görünüşte 0'dan, sonra eski değerden yeni değere sayar.
class KokpitCountUp extends StatelessWidget {
  const KokpitCountUp({
    super.key,
    required this.value,
    required this.builder,
  });

  final int value;
  final Widget Function(BuildContext context, int value) builder;

  @override
  Widget build(BuildContext context) {
    final reduce = kokpitReduceMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? value.toDouble() : 0, end: value.toDouble()),
      duration: reduce ? Duration.zero : KokpitMotion.fill,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => builder(context, v.round()),
    );
  }
}

/// [active] `false` → `true` olduğunda (görev bitti, hedef %100) çocuğu
/// kısaca büyütür ve [color] renginde dışa yayılan bir halka çizer.
/// İlk çizimde zaten `true` ise kutlama yapılmaz.
class KokpitCelebrate extends StatefulWidget {
  const KokpitCelebrate({
    super.key,
    required this.active,
    required this.color,
    required this.child,
  });

  final bool active;
  final Color color;
  final Widget child;

  @override
  State<KokpitCelebrate> createState() => KokpitCelebrateState();
}

class KokpitCelebrateState extends State<KokpitCelebrate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KokpitMotion.celebrate,
  );

  /// Kutlama sayısı (testler ve erişilebilirlik için).
  int celebrations = 0;

  /// Kutlama şu an oynuyor mu.
  bool get playing => _controller.isAnimating;

  @override
  void didUpdateWidget(KokpitCelebrate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      celebrations++;
      if (!kokpitReduceMotion(context)) _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (_, child) {
        // Ağaç şekli sabit: dinlenirken ölçek 1, ressam boş çizer.
        final t = _controller.value;
        final scale = 1 + 0.18 * math.sin(t * math.pi);
        return CustomPaint(
          foregroundPainter: _BurstPainter(progress: t, color: widget.color),
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = size.center(Offset.zero);
    final base = size.shortestSide / 2;
    final eased = Curves.easeOutCubic.transform(progress);
    final fade = 1 - progress;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * fade + 0.5
      ..color = color.withValues(alpha: 0.6 * fade);
    canvas.drawCircle(center, base + base * 0.9 * eased, ring);
    final dot = Paint()..color = color.withValues(alpha: 0.9 * fade);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final r = base + base * 1.3 * eased;
      canvas.drawCircle(
        center + Offset(math.cos(a), math.sin(a)) * r,
        1.8 * fade + 0.4,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.color != color;
}

// ------------------------------------------------------------ günün bölümü

/// Günün bölümü: selamlama kartının rengi buna göre değişir.
enum KokpitDayPhase {
  sabah('Sabah'),
  ogle('Öğle'),
  aksam('Akşam'),
  gece('Gece');

  const KokpitDayPhase(this.label);

  final String label;

  static KokpitDayPhase of(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 12) return sabah;
    if (h >= 12 && h < 18) return ogle;
    if (h >= 18 && h < 22) return aksam;
    return gece;
  }

  /// Kart zemininin geçiş renkleri (pastel roller; kart düşük alfa ile
  /// karıştırır, metin mürekkep renginde kalır, iki temada AA).
  List<Color> get gradient => switch (this) {
        sabah => [AppColors.fitness, AppColors.accent],
        ogle => [AppColors.ops, AppColors.accent],
        aksam => [AppColors.fitness, AppColors.danger],
        gece => [AppColors.sleep, AppColors.ops],
      };

  /// Bölümün işaret rengi (nokta, ikon).
  Color get color => switch (this) {
        sabah => AppColors.fitness,
        ogle => AppColors.ops,
        aksam => AppColors.danger,
        gece => AppColors.sleep,
      };

  IconData get icon => switch (this) {
        sabah => Icons.wb_twilight_rounded,
        ogle => Icons.wb_sunny_outlined,
        aksam => Icons.nights_stay_outlined,
        gece => Icons.bedtime_outlined,
      };
}
