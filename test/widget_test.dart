import 'package:flutter_test/flutter_test.dart';

import 'package:snapcraft_confdb_builder/main.dart';

void main() {
  testWidgets('starts workbench', (WidgetTester tester) async {
    await tester.pumpWidget(const ConfdbBuilderApp());

    expect(find.text('Snapcraft ConfDB Builder'), findsOneWidget);
    expect(find.text('Local drafts'), findsOneWidget);
    expect(find.text('Store schemas'), findsOneWidget);
  });
}
