import 'package:audionotebook/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:logger/web.dart';

Logger logger = Logger();
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Notebook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffcf5b3b)),
        scaffoldBackgroundColor: const Color(0xfff5f0e8),
        // fontFamily: 'Georgia',
      ),
      home: const HomePage(),
    );
  }
}
