import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'pages/workbench_page.dart';

void main() {
  runApp(const ConfdbBuilderApp());
}

class ConfdbBuilderApp extends StatelessWidget {
  const ConfdbBuilderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      builder: (context, yaru, child) {
        return MaterialApp(
          title: 'Snapcraft ConfDB Builder',
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          debugShowCheckedModeBanner: false,
          home: const WorkbenchPage(),
        );
      },
    );
  }
}
