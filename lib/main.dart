import 'package:flutter/material.dart';

void main() => runApp(const TrippingApp());

/// Placeholder shell. Recording (R3/R4) and the map (M1) replace the home
/// screen; the visual language arrives in D1.
class TrippingApp extends StatelessWidget {
  const TrippingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tripping',
      theme: ThemeData(colorSchemeSeed: const Color(0xFFC2410C)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFFC2410C),
        brightness: Brightness.dark,
      ),
      home: const Scaffold(body: Center(child: Text('Tripping'))),
    );
  }
}
