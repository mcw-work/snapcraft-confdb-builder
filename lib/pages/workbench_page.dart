import 'package:flutter/material.dart';

class WorkbenchPage extends StatelessWidget {
  const WorkbenchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Snapcraft ConfDB Builder')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Local drafts'),
            SizedBox(height: 24),
            Text('Store schemas'),
          ],
        ),
      ),
    );
  }
}