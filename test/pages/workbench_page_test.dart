import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/controllers/workbench_controller.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/storage_node.dart';
import 'package:snapcraft_confdb_builder/pages/workbench_page.dart';
import 'package:yaru/yaru.dart';

void main() {
  testWidgets('invalid source does not replace the active document', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = WorkbenchController(
      document: ConfdbSchemaDocument(
        accountId: 'brand',
        name: 'weather',
        summary: 'Weather settings',
        storage: StorageNode.map(children: {'v1': StorageNode.map()}),
      ),
    );

    await tester.pumpWidget(
      YaruTheme(
        builder: (context, yaru, child) => MaterialApp(
          theme: yaru.theme,
          home: WorkbenchPage(controller: controller),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(Tab, 'Source'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('source-editor')), 'not: [yaml');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply source'));
    await tester.pump();

    expect(controller.document.name, 'weather');
    expect(find.textContaining('Invalid YAML'), findsOneWidget);
  });
}