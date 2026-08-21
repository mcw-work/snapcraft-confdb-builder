import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/command_task.dart';
import '../models/confdb_schema_document.dart';
import '../models/diagnostic.dart';
import '../services/account_service.dart';
import '../services/assertion_service.dart';
import '../services/confdb_assertion_builder.dart';
import '../services/confdb_source_codec.dart';
import '../services/confdb_validator.dart';
import '../services/draft_file_service.dart';
import '../services/key_service.dart';
import '../services/schema_diff_service.dart';
import '../services/store_schema_service.dart';
import '../services/terminal_runner.dart';

enum WorkbenchTab { schema, views, source, validation, publish }

@immutable
class _LocalDraft {
  const _LocalDraft({required this.id, required this.document});

  final int id;
  final ConfdbSchemaDocument document;
}

class WorkbenchController extends ChangeNotifier {
  WorkbenchController({
    ConfdbSchemaDocument? document,
    this._validator = const ConfdbValidator(),
    this._codec = const ConfdbSourceCodec(),
    this.assertionBuilder = const ConfdbAssertionBuilder(),
    this.storeSchemaService,
    this.assertionService,
    this.draftFileService,
    this.accountService,
    this.keyService,
  }) : _document =
           document ?? ConfdbSchemaDocument.empty(accountId: '', name: '') {
    _diagnostics = _validator.validate(_document);
  }

  final ConfdbValidator _validator;
  final ConfdbSourceCodec _codec;
  final ConfdbAssertionBuilder assertionBuilder;
  final StoreSchemaService? storeSchemaService;
  final AssertionService? assertionService;
  final DraftFileService? draftFileService;
  final AccountService? accountService;
  final KeyService? keyService;
  final Map<String, RunningCommand> _runningCommands = {};

  ConfdbSchemaDocument _document;
  List<_LocalDraft> _localDraftEntries = const [];
  int _nextLocalDraftId = 0;
  int? _activeLocalDraftId;
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
  List<SigningKey> _keys = const [];
  bool _isBusy = false;

  ConfdbSchemaDocument get document => _document;
  List<ConfdbSchemaDocument> get localDrafts => UnmodifiableListView(
    _localDraftEntries.map((entry) => entry.document),
  );
  List<StoreSchemaRow> get storeRows => UnmodifiableListView(_storeRows);
  List<Diagnostic> get diagnostics => UnmodifiableListView(_diagnostics);
  List<CommandTask> get commandTasks => UnmodifiableListView(_commandTasks);
  WorkbenchTab get selectedTab => _selectedTab;
  String? get selectedViewName => _selectedViewName;
  String? get canonicalSourceFingerprint => _canonicalSourceFingerprint;
    ConfdbSchemaDocument? get preflightRemote => _preflightRemote;
    SchemaComparison? get preflightComparison => _preflightComparison;
    String? get selectedKeyName => _selectedKeyName ?? _document.artifact?.keyName;
      List<SigningKey> get keys => UnmodifiableListView(_keys);
      String? get canonicalUnsignedAssertion => assertionBuilder.build(_document).unsignedInput;
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
    final service = storeSchemaService;
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
    final service = storeSchemaService;
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
    final service = assertionService;
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

  void refreshLocalDrafts() {
    notifyListeners();
  }

  void replaceStoreRows(Iterable<StoreSchemaRow> rows) {
    _storeRows = List.unmodifiable(rows);
    notifyListeners();
  }

  void copyStoreSchema(ConfdbSchemaDocument remote) {
    final revision = remote.revision?.value ?? 'unknown';
    _activeLocalDraftId = _nextLocalDraftId++;
    replaceDocument(
      remote.copyWith(
        origin: DraftOrigin.storeCopy(remoteRevision: revision),
        latestRemote: remote.revision,
      ),
    );
  }

  Future<void> copyStoreRow(StoreSchemaRow row) async {
    final service = storeSchemaService;
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
    _activeLocalDraftId = _nextLocalDraftId++;
    _openDocument(document);
    _upsertLocalDraft(document);
  }

  void openLocalDraftAt(int index) {
    final entry = _localDraftEntries[index];
    _activeLocalDraftId = entry.id;
    _openDocument(entry.document);
  }

  void _openDocument(ConfdbSchemaDocument document) {
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
    final service = storeSchemaService;
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

  Future<void> bootstrap() async {
    final account = accountService;
    final keys = keyService;
    if (account == null || keys == null) {
      return;
    }
    _isBusy = true;
    notifyListeners();
    try {
      final currentAccount = await account.currentAccount();
      _keys = await keys.listKeys();
      if (_document.accountId.isEmpty) {
        _document = _document.copyWith(accountId: currentAccount.id);
        _diagnostics = _validator.validate(_document);
      }
      await refreshStore(currentAccount.id);
    } on AccountServiceException catch (error) {
      _addBootstrapDiagnostic(error.code, error.message);
    } on KeyServiceException catch (error) {
      _addBootstrapDiagnostic(error.code, error.message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> signArtifact({required String savedPath}) async {
    final service = assertionService;
    final keyName = selectedKeyName;
    final unsignedAssertion = canonicalUnsignedAssertion;
    if (service == null || keyName == null || unsignedAssertion == null) {
      return;
    }
    _isBusy = true;
    notifyListeners();
    try {
      final result = await service.sign(
        keyName: keyName,
        unsignedAssertion: unsignedAssertion,
        savedPath: savedPath,
      );
      _document = _document.copyWith(artifact: result.artifact, isDirty: true);
      _upsertLocalDraft(_document);
      recordCommandTask(result.task, notify: false);
    } on AssertionServiceException catch (error) {
      _addBootstrapDiagnostic(error.code, error.message);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> saveDraft(String path) async {
    final service = draftFileService;
    if (service == null) return;
    await service.write(_document, path);
    _document = _document.copyWith(
      origin: DraftOrigin.localFile(path),
      isDirty: false,
    );
    _upsertLocalDraft(_document);
    notifyListeners();
  }

  Future<void> loadDraft(String path) async {
    final service = draftFileService;
    if (service == null) return;
    try {
      openDocument(await service.read(path));
    } on DraftFileServiceException catch (error) {
      _addBootstrapDiagnostic(error.code, error.message);
      notifyListeners();
    }
  }

  void _addBootstrapDiagnostic(String code, String message) {
    _diagnostics = [
      ..._diagnostics.where((diagnostic) => diagnostic.code != code),
      Diagnostic(
        code: code,
        message: message,
        severity: DiagnosticSeverity.blocker,
        location: const DiagnosticLocation(section: 'bootstrap'),
      ),
    ];
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
    final activeDraftId = _activeLocalDraftId ??= _nextLocalDraftId++;
    final index = _localDraftEntries.indexWhere(
      (entry) => entry.id == activeDraftId,
    );
    final drafts = [..._localDraftEntries];
    if (index == -1) {
      drafts.add(_LocalDraft(id: activeDraftId, document: draft));
    } else {
      drafts[index] = _LocalDraft(id: activeDraftId, document: draft);
    }
    _localDraftEntries = List.unmodifiable(drafts);
  }

  String _sourceFingerprint() => _sourceFingerprintFor(_document);

  String _sourceFingerprintFor(ConfdbSchemaDocument document) =>
      sha256.convert(utf8.encode(_codec.encode(document))).toString();
}