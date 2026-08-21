import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/confdb_schema_document.dart';
import 'confdb_source_codec.dart';

abstract interface class DraftPreferences {
  Future<String?> readLastDirectory();

  Future<void> writeLastDirectory(String directory);
}

class SharedPreferencesDraftPreferences implements DraftPreferences {
  SharedPreferencesDraftPreferences(this._preferences);

  static const _lastDirectoryKey = 'draft.lastDirectory';

  final SharedPreferences _preferences;

  static Future<SharedPreferencesDraftPreferences> create() async {
    return SharedPreferencesDraftPreferences(
      await SharedPreferences.getInstance(),
    );
  }

  @override
  Future<String?> readLastDirectory() async =>
      _preferences.getString(_lastDirectoryKey);

  @override
  Future<void> writeLastDirectory(String directory) async {
    await _preferences.setString(_lastDirectoryKey, directory);
  }
}

class DraftFileServiceException implements Exception {
  const DraftFileServiceException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class DraftFileService {
  DraftFileService({
    required this.preferences,
    this.codec = const ConfdbSourceCodec(),
  });

  final DraftPreferences preferences;
  final ConfdbSourceCodec codec;

  Future<ConfdbSchemaDocument> read(String path) async {
    final source = await File(path).readAsString(encoding: utf8);
    final parsed = codec.parse(source);
    if (!parsed.applied) {
      final diagnostic = parsed.diagnostics.first;
      throw DraftFileServiceException(diagnostic.code, diagnostic.message);
    }
    await preferences.writeLastDirectory(File(path).parent.path);
    return parsed.document!.copyWith(
      origin: DraftOrigin.localFile(path),
      isDirty: false,
    );
  }

  Future<void> write(ConfdbSchemaDocument document, String path) async {
    await File(path).writeAsString(codec.encode(document), encoding: utf8);
    await preferences.writeLastDirectory(File(path).parent.path);
  }
}
