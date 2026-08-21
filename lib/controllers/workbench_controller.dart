import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/command_task.dart';
import '../models/confdb_schema_document.dart';
import '../models/diagnostic.dart';
import '../services/assertion_service.dart';
import '../services/confdb_source_codec.dart';
import '../services/confdb_validator.dart';
import '../services/schema_diff_service.dart';
import '../services/store_schema_service.dart';
import '../services/terminal_runner.dart';

enum WorkbenchTab { schema, views, source, validation, publish }

class WorkbenchController extends ChangeNotifier {
  WorkbenchController({
    ConfdbSchemaDocument? document,
    this._validator = const ConfdbValidator(),
    this._codec = const ConfdbSourceCodec(),
    this._storeSchemaService,
    this._assertionService,
  }) : _document =
           document ?? ConfdbSchemaDocument.empty(accountId: '', name: '') {
    _diagnostics = _validator.validate(_document);
  }

  final ConfdbValidator _validator;
  final ConfdbSourceCodec _codec;
  final StoreSchemaService? _storeSchemaService;
  final AssertionService? _assertionService;
  final Map<String, RunningCommand> _runningCommands = {};

  ConfdbSchemaDocument _document;
  List<ConfdbSchemaDocument> _localDrafts = const [];
  List<StoreSchemaRow> _storeRows = const [];
  List<Diagnostic> _diagnostics = const [];
  List<CommandTask> _commandTasks = const [];
  WorkbenchTab _selectedTab = WorkbenchTab.schema;
  String? _selectedViewName;
  String? _canonicalSourceFingerprint;
  String? _preflightFingerprint;
  ConfdbSchemaDocument? _preflightRemote;
  SchemaComparison? _preflightComparison;
  String? _selectedKeyName;
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
    ConfdbSchemaDocument? get preflightRemote => _preflightRemote;
    SchemaComparison? get preflightComparison => _preflightComparison;
    String? get selectedKeyName => _selectedKeyName ?? _document.artifact?.keyName;
    bool get hasBlockers => _diagnostics.any((diagnostic) => diagnostic.isBlocker) ||
      (_preflightComparison?.hasBlockers ?? false);
    bool get preflightCurrent =>
      _preflightFingerprint != null &&
      _preflightFingerprint == _sourceFingerprint();
    bool get canSign => !hasBlockers && (selectedKeyName?.isNotEmpty ?? false);
    bool get canPublish => canSign && preflightCurrent;
  bool get isBusy => _isBusy;
  String get source => _codec.encode(_document);

  void replaceDocument(ConfdbSchemaDocument document) {
    _document = document.copyWith(isDirty: true, artifact: null);
    _commandTasks = const [];
    _runningCommands.clear();
    _canonicalSourceFingerprint = null;
    _preflightFingerprint = null;
    _preflightRemote = null;
    _preflightComparison = null;
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
    _canonicalSourceFingerprint = _sourceFingerprint();
    notifyListeners();
  }

  void selectKey(String? keyName) {
    _selectedKeyName = keyName?.trim().isEmpty ?? true ? null : keyName!.trim();
    notifyListeners();
  }

  Future<void> refreshPreflight() async {
    final service = _storeSchemaService;
    if (service == null || _document.accountId.isEmpty || _document.name.isEmpty) {
      return;
    }
    final fingerprint = _sourceFingerprint();
    _isBusy = true;
    notifyListeners();
    try {
      final result = await service.preflight(_document);
      recordCommandTask(result.task, notify: false);
      if (fingerprint == _sourceFingerprint()) {
        _preflightFingerprint = fingerprint;
        _preflightRemote = result.remote;
        _preflightComparison = result.comparison;
      }
    } on StoreSchemaServiceException catch (error) {
      _diagnostics = [
        ..._diagnostics.where((diagnostic) => diagnostic.location?.section != 'store'),
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

  Future<void> publish() async {
    final service = _storeSchemaService;
    final keyName = selectedKeyName;
    if (service == null || keyName == null || !canPublish) return;
    _isBusy = true;
    notifyListeners();
    try {
      final task = await service.publish(
        accountId: _document.accountId,
        name: _document.name,
        keyName: keyName,
        source: source,
      );
      recordCommandTask(task, notify: false);
      if (task.status == CommandTaskStatus.succeeded) {
        await refreshStore(_document.accountId);
        final remote = await service.fetchRemote(
          accountId: _document.accountId,
          name: _document.name,
        );
        recordCommandTask(remote.task, notify: false);
        _preflightRemote = remote.document;
        _preflightComparison = service.diffService.compare(
          remote: remote.document,
          draft: _document,
        );
        _preflightFingerprint = _sourceFingerprint();
      }
    } on StoreSchemaServiceException catch (error) {
      _diagnostics = [
        ..._diagnostics,
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

  Future<void> acknowledgeArtifact() async {
    final service = _assertionService;
    final savedPath = _document.artifact?.savedPath;
    if (service == null || savedPath == null) return;
    _isBusy = true;
    notifyListeners();
    try {
      final result = await service.acknowledge(savedPath);
      recordCommandTask(result.task, notify: false);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
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
    _preflightFingerprint = null;
    _preflightRemote = null;
    _preflightComparison = null;
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

  String _sourceFingerprint() => sha256.convert(utf8.encode(source)).toString();
}