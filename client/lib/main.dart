import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import 'pages/home.dart';
import 'pages/analysis.dart';

void main() async {
  // Ensure Flutter is initialized before loading assets
  WidgetsFlutterBinding.ensureInitialized();

  // Load the theme file
  final jsonString = await rootBundle.loadString('assets/theme.json');

  runApp(MyApp(themeData: jsonString));
}

class MyApp extends StatelessWidget {
  final String themeData;

  const MyApp({super.key, required this.themeData});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI股票分析',
      theme: ThemeData(extensions: [TDThemeData.fromJson('blue', themeData)!]),
      routes: {
        '/': (context) => const HomePage(),
        '/analysis': (context) => const AnalysisPage(),
      },
    );
  }
}
