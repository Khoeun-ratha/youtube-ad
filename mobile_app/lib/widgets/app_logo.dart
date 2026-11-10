import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// The app's brand blue (the strike through "Ad" in the launcher icon).
const Color _logoBlue = Color(0xFF3B82F6);

/// App bar logo: the launcher icon's crossed-out "Ad" mark plus the
/// "AdFree" wordmark. Drawn in code so it stays sharp at any size.
class AppLogo extends StatelessWidget {
  /// Height of the square mark; the wordmark scales with it.
  final double size;

  /// Show the "AdFree" text next to the mark.
  final bool showWordmark;

  const AppLogo({super.key, this.size = 28, this.showWordmark = true});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AdFree',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppLogoMark(size: size),
          if (showWordmark) ...[
            SizedBox(width: size * 0.3),
            Text.rich(
              TextSpan(
                children: const [
                  TextSpan(text: 'Ad', style: TextStyle(color: AppColors.textPrimary)),
                  TextSpan(text: 'Free', style: TextStyle(color: _logoBlue)),
                ],
                style: TextStyle(
                  fontSize: size * 0.72,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Just the square mark: white "Ad" with a blue strike, on a dark tile.
class AppLogoMark extends StatelessWidget {
  final double size;

  const AppLogoMark({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: const Color(0xFF333333), width: 1),
      ),
      child: CustomPaint(
        foregroundPainter: _StrikePainter(),
        child: Center(
          child: Text(
            'Ad',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.5,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The blue strike across "Ad", same angle as the launcher icon.
class _StrikePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _logoBlue
      ..strokeWidth = size.height * 0.11
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.16, size.height * 0.62),
      Offset(size.width * 0.84, size.height * 0.40),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
