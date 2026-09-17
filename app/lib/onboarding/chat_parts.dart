import 'package:flutter/material.dart';

import 'tour_scenarios.dart';

/// A friend from the tour: their emoji on a soft circle of their colour.
class TourAvatar extends StatelessWidget {
  const TourAvatar(this.scenario, {super.key, required this.size});

  final TourScenario scenario;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = scenario.tint;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(Colors.white, tint, 0.16)!,
            Color.lerp(Colors.white, tint, 0.36)!,
          ],
        ),
        border: Border.all(color: tint.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(scenario.avatar, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

/// The little hook under the last bubble of a run, as in Messages.
class BubbleTail extends CustomPainter {
  BubbleTail({required this.color, required this.mine});
  final Color color;
  final bool mine;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final h = size.height;
    final w = size.width;
    final path = Path();
    if (mine) {
      path
        ..moveTo(w - 14, h - 14)
        ..quadraticBezierTo(w - 4, h - 2, w + 6, h)
        ..quadraticBezierTo(w - 6, h + 1, w - 18, h - 4)
        ..close();
    } else {
      path
        ..moveTo(14, h - 14)
        ..quadraticBezierTo(4, h - 2, -6, h)
        ..quadraticBezierTo(6, h + 1, 18, h - 4)
        ..close();
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(BubbleTail old) => old.color != color || old.mine != mine;
}
