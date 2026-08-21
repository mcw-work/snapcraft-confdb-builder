import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/command_task.dart';
import '../models/confdb_schema_document.dart';
import '../models/diagnostic.dart';
import '../services/confdb_source_codec.dart';
import '../services/confdb_validator.dart';
import '../services/store_schema_service.dart';
import '../services/terminal_runner.dart';

enum WorkbenchTab { schema, views, source, validation, publish }

class WorkbenchController extends ChangeNotifier {
  WorkbenchController({
    ConfdbSchemaDocument? document,
    this._validator = const ConfdbValidator(),
    this._codec = const ConfdbSourceCodec(),
    this._storeSchemaService,
  }) : _document =
           document ?? ConfdbSchemaDocument.empty(accountId: '', name: '') {
    _diagnostics = _validator.validate(_document);
  }

  final ConfdbValidator _validator;
  final ConfdbSourceCodec _codec;
  final StoreSchemaService? _storeSchemaService;
  final Map<String, RunningCommand> _runningCommands = {};

  ConfdbSchemaDocument _document;
  List<ConfdbSchemaDocument> _localDrafts = const [];
  List<StoreSchemaRow> _storeRows = const [];
  List<Diagnostic> _diagnostics = const [];
  List<CommandTask> _commandTasks = const [];
  WorkbenchTab _selectedTab = WorkbenchTab.schema;
  String? _selectedViewName;
  String? _canonicalSourceFingerprint;
  bool _isBusy = false;

  ConfdbSchemaDocument get document => _document;
  List<ConfdbSchemaDocument> get localDrafts =>
      UnmodifiableListView(_localDrafts);
  List<StoreSchemaRow> get storeRows => UnmodifiableListView(_storeRows);
  List<Diagnostic> get diagnostics => UnmodifiableListView(_diagnostics);
  List<CommandTask> get commandTasks => UnmodifiableListView(_commandTasks);
  WorkbenchTab get selectedTab => _selectedTab;
  String? get selectedViewName => _selectedViewName;
  String? get canonicalSourceFingerprint => _canonicalSourceFingerprint;
  bool get isBusy => _isBusy;
  String get source => _codec.encode(_document);

  void replaceDocument(ConfdbSchemaDocument document) {
    _document = document.copyWith(isDirty: true, artifact: null);
    _commandTasks = const [];
    _runningCommands.clear();
    _canonicalSourceFingerprint = null;
    _diagnostics = _validator.validate(_document);
    _upsertLocalDraft(_document);
    notifyListeners();
  }

  bool applySource(String source) {
    final result = _codec.applySource(_document, source);
    if (!result.applied) {
      _diagnostics = result.diagnostics;
      notifyListeners();
      return false;
    }
    replaceDocument(result.document!);
    return true;
  }

  void cacheCanonicalSourceFingerprint() {
    _canonicalSourceFingerprint = sha256.convert(utf8.encode(source)).toString();
    notifyListeners();
  }

  void selectTab(WorkbenchTab tab) {
    if (_selectedTab == tab) {
      return;
    }
    _selectedTab = tab;
    notifyListeners();
  }

  void selectView(String? viewName) {
    if (_selectedViewName == viewName) {
      return;
    }
    _selectedViewName = viewName;
    notifyListeners();
  }

  void replaceLocalDrafts(Iterable<ConfdbSchemaDocument> drafts) {
    _localDrafts = List.unmodifiable(drafts);
    notifyListeners();
  }

  void replaceStoreRows(Iterable<StoreSchemaRow> rows) {
    _storeRows = List.unmodifiable(rows);
    notifyListeners();
  }

  void copyStoreSchema(ConfdbSchemaDocument remote) {
    final revision = remote.revision?.value ?? 'unknown';
    replaceDocument(
      remote.copyWith(
        origin: DraftOrigin.storeCopy(remoteRevision: revision),
        latestRemote: remote.revision,
      ),
    );
  }

  Future<void> copyStoreRow(StoreSchemaRow row) async {
    final service = _storeSchemaService;
    if (service == null) return;
    _isBusy = true;
    notifyListeners();
    try {
      final result = await service.fetchRemote(
        accountId: row.accountId,
        name: row.name,
      );
      recordCommandTask(result.task, notify: false);
      copyStoreSchema(result.document);
    } on StoreSchemaServiceException catch (error) {
      _diagnostics = [
        Diagnostic(
          code: error.code,
          message: error.message,
          severity: DiagnosticSeverity.blocker,
          location: const DiagnosticLocation(section: 'store'),
        ),
      ];
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void openDocument(ConfdbSchemaDocument document) {
    _document = document;
    _diagnostics = _validator.validate(document);
    _canonicalSourceFingerprint = null;
    _commandTasks = const [];
    _runningCommands.clear();
    notifyListeners();
  }

  void markSaved() {
    _document = _document.copyWith(isDirty: false);
    _upsertLocalDraft(_document);
    notifyListeners();
  }

  Future<void> refreshStore(String accountId) async {
    final service = _storeSchemaService;
    if (service == null) {
      return;
    }
    _isBusy = true;
    notifyListeners();
    try {
      final result = await service.inventory(accountId);
      _storeRows = result.rows;
      _diagnostics = result.diagnostics;
      recordCommandTask(result.task, notify: false);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void recordCommandTask(CommandTask task, {bool notify = true}) {
    _commandTasks = List.unmodifiable([..._commandTasks, task]);
    if (notify) {
      notifyListeners();
    }
  }

  void registerRunningCommand(String taskId, RunningCommand command) {
    _runningCommands[taskId] = command;
  }

  Future<void> cancelCommand(String taskId) async {
    final command = _runningCommands.remove(taskId);
    if (command == null) {
      return;
    }
    await command.cancel();
    _commandTasks = List.unmodifiable([
      for (final task in _commandTasks)
        if (task.id == taskId && !task.isFinished)
          task.copyWith(status: CommandTaskStatus.cancelled)
        else
          task,
    ]);
    notifyListeners();
  }

  void _upsertLocalDraft(ConfdbSchemaDocument draft) {
    final index = _localDrafts.indexWhere(
      (candidate) =>
          candidate.accountId == draft.accountId && candidate.name == draft.name,
    );
    final drafts = [..._localDrafts];
    if (index == -1) {
      drafts.add(draft);
    } else {
      drafts[index] = draft;
    }
    _localDrafts = List.unmodifiable(drafts);
  }
}