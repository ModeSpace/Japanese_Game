import 'package:flutter/material.dart';
import 'draw_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Learning JP',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DrawingPage(),
    );
  }
}
