import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapcraft_confdb_builder/models/confdb_schema_document.dart';
import 'package:snapcraft_confdb_builder/models/diagnostic.dart';
import 'package:snapcraft_confdb_builder/services/schema_diff_service.dart';
import 'package:snapcraft_confdb_builder/widgets/publish_panel.dart';

void main() {
  testWidgets('blockers disable publish after preflight', (tester) async {
    var preflighted = false;
    final remote = _document(summary: 'Remote weather settings');
    final draft = _document();
    final comparison = const SchemaDiffService().compare(
      remote: remote,
      draft: draft,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: PublishPanel(
              document: draft,
              unsignedAssertion: 'type: confdb-schema\n',
              keys: const [],
              selectedKeyName: 'developer-key',
              diagnostics: const [
                Diagnostic(
                  code: 'schema.invalid',
                  message: 'Fix the schema before publishing.',
                  severity: DiagnosticSeverity.blocker,
                ),
              ],
              remote: preflighted ? remote : null,
              comparison: preflighted ? comparison : null,
              preflightCurrent: preflighted,
              onRefreshPreflight: () => setState(() => preflighted = true),
              onSelectKey: (_) {},
              onSign: () {},
              onRunAck: () {},
              onPublish: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Refresh preflight'));
    await tester.pump();

    expect(find.textContaining('--- remote'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('publish-button'))).onPressed,
      isNull,
    );
  });

  testWidgets('shows the supplied canonical unsigned assertion and runs acknowledgement', (tester) async {
    var acknowledgements = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublishPanel(
            document: _document().copyWith(
              artifact: SigningArtifact(
                keyName: 'developer-key',
                signedAssertion: 'signed assertion',
                savedPath: '/tmp/weather.assert',
                createdAt: DateTime(2026),
              ),
            ),
            unsignedAssertion: 'type: confdb-schema\nbody: |-\n  {}\n',
            keys: const [],
            selectedKeyName: 'developer-key',
            diagnostics: const [],
            remote: null,
            comparison: null,
            preflightCurrent: true,
            onRefreshPreflight: () {},
            onSelectKey: (_) {},
            onSign: () {},
            onRunAck: () => acknowledgements++,
            onPublish: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('body: |-'), findsOneWidget);
    await tester.tap(find.text('Run snap ack'));
    expect(acknowledgements, 1);
  });
}

ConfdbSchemaDocument _document({String summary = 'Weather settings'}) =>
    ConfdbSchemaDocument.empty(accountId: 'brand', name: 'weather').copyWith(
      summary: summary,
    );