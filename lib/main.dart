import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'controllers/workbench_controller.dart';
import 'pages/workbench_page.dart';
import 'services/account_service.dart';
import 'services/assertion_service.dart';
import 'services/draft_file_service.dart';
import 'services/key_service.dart';
import 'services/snapcraft_env.dart';
import 'services/store_schema_service.dart';
import 'services/terminal_runner.dart';

void main() {
  runApp(const ConfdbBuilderApp());
}

class ConfdbBuilderApp extends StatefulWidget {
  const ConfdbBuilderApp({super.key, this.controller});

  final WorkbenchController? controller;

  @override
  State<ConfdbBuilderApp> createState() => _ConfdbBuilderAppState();
}

class _ConfdbBuilderAppState extends State<ConfdbBuilderApp> {
  late final Future<WorkbenchController> _controller = widget.controller == null
      ? _createController()
      : Future.value(widget.controller);

  Future<WorkbenchController> _createController() async {
    final runner = ProcessTerminalRunner();
    const environment = SnapcraftEnvironment();
    return WorkbenchController(
      accountService: AccountService(
        runner: runner,
        snapcraftEnvironment: environment,
      ),
      assertionService: AssertionService(runner: runner),
      draftFileService: DraftFileService(
        preferences: await SharedPreferencesDraftPreferences.create(),
      ),
      keyService: KeyService(runner: runner, snapcraftEnvironment: environment),
      storeSchemaService: StoreSchemaService(
        runner: runner,
        snapcraftEnvironment: environment,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      builder: (context, yaru, child) {
        return MaterialApp(
          title: 'Snapcraft ConfDB Builder',
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          debugShowCheckedModeBanner: false,
          home: FutureBuilder<WorkbenchController>(
            future: _controller,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return WorkbenchPage(controller: snapshot.data!);
              }
              if (snapshot.hasError) {
                return Scaffold(
                  body: Center(
                    child: Text('Unable to initialise: ${snapshot.error}'),
                  ),
                );
              }
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            },
          ),
        );
      },
    );
  }
}
