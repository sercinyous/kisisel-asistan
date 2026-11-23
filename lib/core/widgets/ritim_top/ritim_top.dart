import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'ritim_top_geometry.dart';

/// [RitimTop] hareket kipi.
enum RitimTopMode {
  /// Yükleniyor: uç noktası çevresinde hafif yalpalayarak sürekli döner.
  spin,

  /// Varış/başarı: hızlı döner, yavaşlar ve simge duruşuna oturur; bir kez.
  settle,

  /// Durağan simge duruşu.
  idle,
}

/// Uygulama simgesindeki topaç; yükleme ve varış animasyonu. [color]
/// verilmezse simgedeki gibi gün batımı koni, neon halka ve altın sap çizilir.
///
/// Hareket azaltma açıksa (`MediaQuery.disableAnimations`) her kipte durağan
/// duruş çizilir; [RitimTopMode.settle] yine de [onDone] çağırır.
class RitimTop extends StatefulWidget {
  const RitimTop({
    super.key,
    this.mode = RitimTopMode.spin,
    this.size = 48,
    this.color,
    this.semanticsLabel,
    this.onDone,
  });

  final RitimTopMode mode;

  /// Kare kenarı (mantıksal piksel).
  final double size;

  /// Verilirse tek renk; verilmezse Vice City simge renkleri.
  final Color? color;

  /// Verilmezse dönerken "Yükleniyor"; öbür kiplerde süs sayılır.
  final String? semanticsLabel;

  /// [RitimTopMode.settle] duruşa oturunca bir kez çağrılır.
  final VoidCallback? onDone;

  static const Duration spinDuration = Duration(milliseconds: 1600);
  static const Duration settleDuration = Duration(milliseconds: 1400);

  @override
  State<RitimTop> createState() => _RitimTopState();
}

class _RitimTopState extends State<RitimTop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);
  bool? _reduced;
  bool _doneReported = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced != _reduced) {
      _reduced = reduced;
      _start();
    }
  }

  @override
  void didUpdateWidget(RitimTop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _doneReported = false;
      _start();
    }
  }

  void _start() {
    _controller.stop();
    final reduced = _reduced ?? false;
    switch (widget.mode) {
      case RitimTopMode.spin:
        if (reduced) {
          _controller.value = 0;
        } else {
          _controller
            ..duration = RitimTop.spinDuration
            ..repeat();
        }
      case RitimTopMode.settle:
        if (reduced) {
          _controller.value = 1;
          WidgetsBinding.instance.addPostFrameCallback((_) => _reportDone());
        } else {
          _controller
            ..duration = RitimTop.settleDuration
            ..forward(from: 0);
        }
      case RitimTopMode.idle:
        _controller.value = 0;
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        widget.mode == RitimTopMode.settle) {
      _reportDone();
    }
  }

  void _reportDone() {
    if (!mounted || _doneReported || widget.mode != RitimTopMode.settle) return;
    _doneReported = true;
    widget.onDone?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = _reduced ?? false;
    final label = widget.semanticsLabel ??
        (widget.mode == RitimTopMode.spin ? 'Yükleniyor' : null);
    final paint = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _RitimTopPainter(
          progress: _controller,
          mode: reduced ? RitimTopMode.idle : widget.mode,
          color: widget.color ?? AppColors.neonTeal,
          vice: widget.color == null
              ? RitimTopColors(
                  cone: AppColors.sunset,
                  ring: AppColors.neonTeal,
                  handle: [AppColors.sunsetStart, AppColors.sunsetMid],
                )
              : null,
        ),
      ),
    );
    if (label == null) return ExcludeSemantics(child: paint);
    return Semantics(label: label, child: paint);
  }
}

/// Simge renkleri: koni ve sap dikey geçiş, halka düz neon.
@immutable
class RitimTopColors {
  const RitimTopColors({
    required this.cone,
    required this.ring,
    required this.handle,
  });

  final List<Color> cone;
  final Color ring;
  final List<Color> handle;

  @override
  bool operator ==(Object other) =>
      other is RitimTopColors &&
      listEquals(other.cone, cone) &&
      other.ring == ring &&
      listEquals(other.handle, handle);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(cone), ring, Object.hashAll(handle));
}

/// Bir karedeki duruş; önizleme sayfasındaki hesapla aynıdır.
@immutable
class RitimTopPose {
  const RitimTopPose({
    this.tilt = 0,
    this.scale = 1,
    this.stretch = 0,
    this.opacity = 1,
    this.highlightAngle = 0,
    this.highlight = 0,
    this.shadow = 0,
    this.shadowScale = 1,
    this.shadowShift = 0,
  });

  /// Simge duruşu.
  static const RitimTopPose rest = RitimTopPose();

  /// Uç çevresinde dönüş (radyan).
  final double tilt;

  /// Uç çevresinde eş ölçek.
  final double scale;

  /// Yalpalamanın öne/arkaya bileşeni: yatayda `1 + stretch`, dikeyde
  /// `1 - stretch`.
  final double stretch;
  final double opacity;

  /// Halkadaki ışık diliminin açısı (radyan) ve görünürlüğü (0..1).
  final double highlightAngle;
  final double highlight;

  /// Yer gölgesinin görünürlüğü (0..1), genişlik ölçeği ve yatay kayması.
  final double shadow;
  final double shadowScale;
  final double shadowShift;

  static const double _tau = 2 * math.pi;

  /// [progress] (0..1) için [mode] duruşu.
  static RitimTopPose at(RitimTopMode mode, double progress) {
    switch (mode) {
      case RitimTopMode.idle:
        return rest;
      case RitimTopMode.spin:
        final a = _tau * progress;
        return RitimTopPose(
          tilt: 0.06 * math.sin(a),
          stretch: 0.02 * math.cos(a),
          highlightAngle: a,
          highlight: 1,
          shadow: 1,
          shadowScale: 1 + 0.08 * math.cos(a),
          shadowShift: 1.5 * math.sin(a),
        );
      case RitimTopMode.settle:
        final t = progress.clamp(0.0, 1.0);
        final eased = 1 - math.pow(1 - t, 3).toDouble();
        final a = _tau * 3 * eased;
        final damp = (1 - t) * (1 - t);
        final u = math.min(t / 0.45, 1.0) - 1;
        final back = 1 + 2.70158 * u * u * u + 1.70158 * u * u;
        final fade = ((1 - t) / 0.4).clamp(0.0, 1.0);
        return RitimTopPose(
          tilt: 0.26 * damp * math.sin(a),
          scale: 0.6 + 0.4 * back,
          stretch: 0.03 * damp * math.cos(a),
          opacity: (t / 0.12).clamp(0.0, 1.0),
          highlightAngle: a,
          highlight: fade,
          shadow: fade,
          shadowScale: 1 + 0.1 * damp * math.cos(a),
          shadowShift: 5 * damp * math.sin(a),
        );
    }
  }
}

class _RitimTopPainter extends CustomPainter {
  _RitimTopPainter({
    required this.progress,
    required this.mode,
    required this.color,
    this.vice,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final RitimTopMode mode;
  final Color color;
  final RitimTopColors? vice;

  Paint _fill(Path path, List<Color>? colors, Color fallback) {
    final paint = Paint()
      ..color = fallback.withValues(alpha: 1)
      ..isAntiAlias = true;
    if (colors != null) {
      final b = path.getBounds();
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(b);
    }
    return paint;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pose = RitimTopPose.at(mode, progress.value);
    final unit = size.shortestSide / RitimTopGeometry.viewBox;
    canvas
      ..save()
      ..translate(
        (size.width - size.shortestSide) / 2,
        (size.height - size.shortestSide) / 2,
      )
      ..scale(unit);

    if (pose.shadow > 0) {
      final center = RitimTopGeometry.shadowCenter;
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(pose.shadowShift, 0),
          width: 2 * RitimTopGeometry.shadowRadiusX * pose.shadowScale,
          height: 2 * RitimTopGeometry.shadowRadiusY,
        ),
        Paint()
          ..color = color.withValues(alpha: 0.16 * pose.shadow * pose.opacity),
      );
    }

    final layered = pose.opacity < 1;
    if (layered) {
      canvas.saveLayer(
        const Rect.fromLTWH(-50, -50, 200, 200),
        Paint()..color = color.withValues(alpha: pose.opacity),
      );
    }

    final tip = RitimTopGeometry.tip;
    canvas
      ..save()
      ..translate(tip.dx, tip.dy)
      ..rotate(pose.tilt)
      ..scale(pose.scale * (1 + pose.stretch), pose.scale * (1 - pose.stretch))
      ..translate(-tip.dx, -tip.dy);

    final v = vice;
    canvas
      ..drawPath(
          RitimTopGeometry.cone, _fill(RitimTopGeometry.cone, v?.cone, color))
      ..drawPath(RitimTopGeometry.ring,
          _fill(RitimTopGeometry.ring, null, v?.ring ?? color));
    if (pose.highlight > 0) _paintHighlight(canvas, pose);
    canvas
      ..drawPath(RitimTopGeometry.handle,
          _fill(RitimTopGeometry.handle, v?.handle, color))
      ..restore();

    if (layered) canvas.restore();
    canvas.restore();
  }

  /// Halka boyunca dolaşan açık renkli dilim; dönüş izlenimini verir.
  void _paintHighlight(Canvas canvas, RitimTopPose pose) {
    final hsl = HSLColor.fromColor(color);
    final light =
        hsl.withLightness(hsl.lightness + (1 - hsl.lightness) * 0.6).toColor();
    final center = RitimTopGeometry.ringCenter;
    canvas
      ..save()
      ..clipPath(RitimTopGeometry.ring)
      ..translate(center.dx, center.dy)
      ..rotate(RitimTopGeometry.ringTilt)
      ..scale(1, RitimTopGeometry.ringSquash);
    const reach = Rect.fromLTRB(-60, -60, 60, 60);
    for (final (span, alpha) in const [(1.5, 0.35), (0.7, 0.5)]) {
      final wedge = Path()
        ..moveTo(0, 0)
        ..arcTo(reach, pose.highlightAngle - span / 2, span, false)
        ..close();
      canvas.drawPath(
        wedge,
        Paint()..color = light.withValues(alpha: alpha * pose.highlight),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RitimTopPainter oldDelegate) =>
      oldDelegate.mode != mode ||
      oldDelegate.color != color ||
      oldDelegate.vice != vice ||
      oldDelegate.progress != progress;
}
