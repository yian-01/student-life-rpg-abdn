import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

class MemoryCampusDocuments implements JsonDocumentStore {
  final documents = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> readDocument(String path) async => documents[path];
  @override
  Future<void> writeDocument(String path, String content) async {
    if (failWrites) throw StateError('Injected disk failure');
    if (documents.containsKey(path)) documents['$path.bak'] = documents[path]!;
    documents[path] = content;
  }
}

CampusData emptyCampusData() =>
    CampusData(CampusStore(MemoryCampusDocuments(), 'campus.json'));
