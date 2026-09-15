import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The glass orb — Glyf's onboarding signature (reference: Acti's
/// drag-to-choose bubble, rebuilt in our own language). A refractive glass
/// sphere that floats, carries a label, and can be dragged onto targets.
class GlassOrb extends StatefulWidget {
  const GlassOrb({
    super.key,
    this.size = 180,
    this.label,
    this.sublabel,
    this.floating = true,
  });

  final double size;
  final String? label;
  final String? sublabel;
  final bool floating;

  @override
  State<GlassOrb> createState() => _GlassOrbState();
}

class _GlassOrbState extends State<GlassOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orb = _orbBody();
    if (!widget.floating) return orb;
    return AnimatedBuilder(
      animation: _bob,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_bob.value);
        return Transform.translate(offset: Offset(0, lerpDouble(-7, 7, t)!), child: child);
      },
      child: orb,
    );
  }

  Widget _orbBody() {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft ground glow
          Positioned(
            bottom: -s * 0.06,
            child: Container(
              width: s * 0.7,
              height: s * 0.16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(s),
                boxShadow: [
                  BoxShadow(
                    color: Glass.accent.withValues(alpha: 0.16),
                    blurRadius: 36,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          // The sphere: blurred backdrop + radial glass + rim light
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.45),
                    radius: 1.1,
                    colors: [
                      Colors.white,
                      const Color(0xFFF4F5F9),
                      Glass.accent.withValues(alpha: 0.07),
                      const Color(0xFFE9EBF1),
                    ],
                    stops: const [0.0, 0.38, 0.75, 1.0],
                  ),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
              ),
            ),
          ),
          // Specular highlight
          Positioned(
            top: s * 0.12,
            left: s * 0.18,
            child: Container(
              width: s * 0.34,
              height: s * 0.18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(s),
                gradient: LinearGradient(
                  colors: [
                    Colors.white,
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          // Label — "refracted" via slight chromatic double-draw
          if (widget.label != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Transform.translate(
                      offset: const Offset(1.2, 0.6),
                      child: Text(
                        widget.label!,
                        style: TextStyle(
                          fontSize: s * 0.16,
                          fontWeight: FontWeight.w800,
                          color: Glass.accent.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    Text(
                      widget.label!,
                      style: TextStyle(
                        fontSize: s * 0.16,
                        fontWeight: FontWeight.w800,
                        color: Glass.ink,
                      ),
                    ),
                  ],
                ),
                if (widget.sublabel != null)
                  Padding(
                    padding: EdgeInsets.only(top: s * 0.02),
                    child: Text(
                      widget.sublabel!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: s * 0.062,
                        color: Glass.inkSoft,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Drag-to-choose (the Acti-reference interaction): drag the orb onto a
/// target card to pick it.
class DraggableOrb extends StatelessWidget {
  const DraggableOrb({super.key, required this.payload, this.size = 120});

  final String payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    final orb = GlassOrb(size: size, label: '', floating: true);
    return Draggable<String>(
      data: payload,
      feedback: GlassOrb(size: size * 0.9, floating: false),
      childWhenDragging: Opacity(opacity: 0.25, child: orb),
      child: orb,
    );
  }
}
