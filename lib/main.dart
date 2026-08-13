import 'package:flutter/material.dart';

import 'ui/home_page.dart';

void main() {
  runApp(const VidBoxApp());
}

class VidBoxApp extends StatelessWidget {
  const VidBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VidBox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
