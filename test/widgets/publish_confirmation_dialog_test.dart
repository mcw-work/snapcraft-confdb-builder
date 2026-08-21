import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/widgets/publish_confirmation_dialog.dart';

void main() {
  testWidgets('exact schema name enables confirmation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => PublishConfirmationDialog(
                  schemaName: 'weather',
                  onConfirm: () {},
                ),
              ),
              child: const Text('Open confirmation'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open confirmation'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('schema-name-confirmation')),
      'Weather',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-publish-button')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('schema-name-confirmation')),
      'weather',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-publish-button')))
          .onPressed,
      isNotNull,
    );
  });
}