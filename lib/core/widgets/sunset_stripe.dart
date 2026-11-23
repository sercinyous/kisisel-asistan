import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Vice City esintisi: ince, yuvarlak uçlu gün batımı şeridi
/// (sarı → mercan → macenta → neon). Süs öğesidir; metin taşımaz.
class SunsetStripe extends StatelessWidget {
  const SunsetStripe({super.key, this.width = 44, this.height = 3});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            gradient: LinearGradient(
              colors: [...AppColors.sunset, AppColors.neonTeal],
              stops: const [0, 0.4, 0.75, 1],
            ),
          ),
        ),
      ),
    );
  }
}
