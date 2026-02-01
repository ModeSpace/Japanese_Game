import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as ml;
import 'package:perfect_freehand/perfect_freehand.dart';

class DrawingPage extends StatefulWidget {
  const DrawingPage({super.key});

  @override
  State<DrawingPage> createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage> {
  final List<Offset> _points = [];
  late FocusNode _focusNode;

  final String _languageCode = 'ja';
  late final ml.DigitalInkRecognizer _digitalInkRecognizer;
  final ml.DigitalInkRecognizerModelManager _modelManager = ml.DigitalInkRecognizerModelManager();

  @override
  void initState() {
    super.initState();
    _digitalInkRecognizer = ml.DigitalInkRecognizer(languageCode: _languageCode);
    _focusNode = FocusNode();
    _downloadModel();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _downloadModel() async {
    try {
      final bool isDownloaded = await _modelManager.isModelDownloaded(_languageCode);
      if (!isDownloaded) {
        debugPrint('Downloading Japanese model...');
        await _modelManager.downloadModel(_languageCode);
        debugPrint('Download complete.');
      }
    } catch (e) {
      debugPrint('Model download error: $e');
    }
  }

  void _onPanStart(DragStartDetails details) => setState(() => _points.add(details.localPosition));
  void _onPanUpdate(DragUpdateDetails details) => setState(() => _points.add(details.localPosition));
  void _onPanEnd(DragEndDetails details) => setState(() => _points.add(Offset.zero));

  void _clear() => setState(() => _points.clear());

  Future<void> _checkKanji(String expectedKanji) async {
    if (_points.isEmpty) return;

    final ink = ml.Ink();
    List<ml.StrokePoint> currentStrokePoints = [];

    for (final point in _points) {
      if (point == Offset.zero) {
        if (currentStrokePoints.isNotEmpty) {
          final stroke = ml.Stroke();
          stroke.points = List.of(currentStrokePoints);
          ink.strokes.add(stroke);
          currentStrokePoints = [];
        }
      } else {
        currentStrokePoints.add(ml.StrokePoint(
          x: point.dx,
          y: point.dy,
          t: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    }

    try {
      final List<ml.RecognitionCandidate> candidates = await _digitalInkRecognizer.recognize(ink);
      
      bool isCorrect = false;
      String detected = "nothing";

      if (candidates.isNotEmpty) {
        detected = candidates.first.text;
        isCorrect = candidates.any((c) => 
          c.text.contains(expectedKanji) || 
          (expectedKanji == 'カ' && c.text.contains('力'))
        );
      }

      _showSnackBar(isCorrect ? '✓ Correct! Detected: $detected' : '✗ Try again. Detected: $detected');
    } catch (e) {
      debugPrint('Recognition error: $e');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _digitalInkRecognizer.close();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Japanese Drawing'),
        actions: [
          IconButton(onPressed: _clear, icon: const Icon(Icons.delete)),
          IconButton(onPressed: () => _checkKanji('カ'), icon: const Icon(Icons.check)),
        ],
      ),
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (event.logicalKey == LogicalKeyboardKey.space && event is KeyDownEvent) {
            _clear();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: CustomPaint(
            size: Size.infinite,
            painter: _FreehandPainter(List.of(_points)),
          ),
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
          ..color = const Color.fromARGB(255, 0, 0, 0)
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
