import 'dart:async';

import 'package:flutter/material.dart';

class AnimatedDots extends StatelessWidget {
  const AnimatedDots({super.key, this.maxDots = 3, this.period = _SharedDotsTicker.tick, this.style})
    : assert(maxDots > 0);

  final int maxDots;
  final Duration period;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    assert(
      period == _SharedDotsTicker.tick,
      'AnimatedDots uses a shared ticker with period ${_SharedDotsTicker.tick}.',
    );
    return StreamBuilder<int>(
      stream: _SharedDotsTicker.stream,
      builder: (context, snapshot) {
        final count = (snapshot.data ?? 0) % (maxDots + 1);
        final dots = List.filled(count, '.').join();
        final padded = dots.padRight(maxDots, ' ');
        final factor = maxDots == 0 ? 0.0 : (count / maxDots);
        final opacity = 0.55 + (0.45 * factor);
        final scale = 0.96 + (0.06 * factor);
        return AnimatedOpacity(
          duration: period,
          opacity: opacity,
          child: AnimatedScale(
            duration: period,
            scale: scale,
            child: Text(padded, style: style),
          ),
        );
      },
    );
  }
}

class _SharedDotsTicker {
  static const Duration tick = Duration(milliseconds: 240);

  static final StreamController<int> _controller = StreamController<int>.broadcast(
    onListen: _start,
    onCancel: _stopIfIdle,
  );

  static Timer? _timer;
  static int _count = 0;

  static Stream<int> get stream => _controller.stream;

  static void _start() {
    if (_timer != null) return;
    _timer = Timer.periodic(tick, (_) {
      _count = (_count + 1) % 1000000;
      _controller.add(_count);
    });
  }

  static void _stopIfIdle() {
    if (_controller.hasListener) return;
    _timer?.cancel();
    _timer = null;
  }
}
