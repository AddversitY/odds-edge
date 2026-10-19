import 'package:odds_edge/data/research_store.dart';
import 'package:odds_edge/domain/research.dart';
import 'package:odds_edge/domain/autopsy.dart';

class MemoryResearchStore extends ResearchStore {
  final Map<String, ResearchReview> reviews = {};
  @override
  Future<Map<String, ResearchReview>> loadReviews() async => reviews;
  @override
  Future<void> saveReview(ResearchReview r) async {
    reviews[r.researchKey] = r;
  }

  final List<SavedResearch> records = [];
  final Map<String, SavedResearch> drafts = {};
  SavedResearch? latest;
  Set<String>? books;
  @override
  Future<List<SavedResearch>> load() async => records.reversed.toList();
  @override
  Future<void> save(SavedResearch r) async {
    records.add(r);
  }

  @override
  Future<void> saveDraft(SavedResearch r) async {
    latest = r;
    drafts[r.context.identity] = r;
  }

  @override
  Future<SavedResearch?> loadDraft({String? selectionKey}) async =>
      selectionKey == null ? latest : drafts[selectionKey];
  @override
  Future<Set<String>?> loadBooks() async => books;
  @override
  Future<void> saveBooks(Set<String>? value) async {
    books = value;
  }
}
