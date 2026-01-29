import 'dart:async';
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

class DrawingPage extends StatefulWidget {
  const DrawingPage({super.key});

  @override
  State<DrawingPage> createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage> {
  final List<Offset> _points = [];
  Timer? _idleTimer;
  bool _isPointerDown = false;

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    // Don't schedule clearing while the pointer is down (holding left click)
    if (_isPointerDown) return;
    _idleTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) {
        setState(() => _points.clear());
      }
    });
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _isPointerDown = true;
      _points.add(details.localPosition);
    });
    // Ensure any pending clear is canceled while user holds down
    _idleTimer?.cancel();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _points.add(details.localPosition);
    });
    // Keep the timer canceled while pointer remains down
    _idleTimer?.cancel();
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _isPointerDown = false;
      // break stroke with a null marker
      _points.add(Offset.zero);
    });
    _resetIdleTimer();
  }

  void _onPanCancel() {
    setState(() {
      _isPointerDown = false;
    });
    _resetIdleTimer();
  }

  void _clear() {
    _idleTimer?.cancel();
    setState(() => _points.clear());
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drawing Page'),
        actions: [
          IconButton(onPressed: _clear, icon: const Icon(Icons.delete)),
        ],
      ),
      body: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,        onPanCancel: _onPanCancel,        child: CustomPaint(
          size: Size.infinite,
          painter: _FreehandPainter(List.of(_points)),
        ),
      ),
    );
  }
}

class _FreehandPainter extends CustomPainter {
  final List<Offset> points;
  final Paint _paint = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.fill;

  _FreehandPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // Split into strokes separated by a zero-offset sentinel
    final List<List<Offset>> strokes = [];
    List<Offset> current = [];
    for (var p in points) {
      if (p == Offset.zero) {
        if (current.isNotEmpty) {
          strokes.add(current);
          current = [];
        }
      } else {
        current.add(p);
      }
    }
    if (current.isNotEmpty) strokes.add(current);

    for (var stroke in strokes) {
      // If the stroke contains a single point (tap without move), draw a dot
      if (stroke.length == 1) {
        canvas.drawCircle(stroke[0], 8.0, _paint);
        continue;
      }
      if (stroke.length < 2) continue;

      // Convert stroke to the format expected by `perfect_freehand`.
      // The JS library expects points as [[x, y, pressure?], ...].
      // The Dart port exposes `getStroke` which accepts a List<List<double>>.
      try {
        final List<PointVector> input = stroke.map((o) => PointVector(o.dx, o.dy)).toList();
        // getStroke returns a list of Offset outlining the stroke.
        final outline = getStroke(
          input,
          options: StrokeOptions(size: 16, simulatePressure: true),
        );

        final path = Path();
        if (outline.isNotEmpty) {
          path.moveTo(outline[0].dx, outline[0].dy);
          for (var pt in outline) {
            path.lineTo(pt.dx, pt.dy);
          }
          path.close();
          canvas.drawPath(path, _paint);
        }
      } catch (e) {
        // Fallback: smooth path using quadratic beziers
        final path = Path()..moveTo(stroke[0].dx, stroke[0].dy);
        for (var i = 1; i < stroke.length - 1; i++) {
          final p0 = stroke[i];
          final p1 = stroke[i + 1];
          final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
          path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
        }
        // finish
        path.lineTo(stroke.last.dx, stroke.last.dy);
        final strokePaint = Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, strokePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FreehandPainter oldDelegate) => true;
}
