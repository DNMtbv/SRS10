import 'package:drift/drift.dart';

import '../core/app_exception.dart';
import '../core/clock.dart';
import '../core/validators.dart';
import '../database/app_database.dart';
import '../models/views.dart';

class CommentRepository {
  CommentRepository(this._db, {Clock clock = systemClock}) : _now = clock;

  final AppDatabase _db;
  final Clock _now;

  Stream<List<CommentView>> watchComments(int taskId) {
    final query = _db.select(_db.comments).join([
      leftOuterJoin(_db.users, _db.users.id.equalsExp(_db.comments.authorId)),
    ])
      ..where(_db.comments.taskId.equals(taskId))
      ..orderBy([
        OrderingTerm.asc(_db.comments.createdAt),
        OrderingTerm.asc(_db.comments.id),
      ]);
    return query.watch().map(
          (rows) => rows
              .map(
                (r) => CommentView(
                  comment: r.readTable(_db.comments),
                  authorName: r.readTableOrNull(_db.users)?.name,
                ),
              )
              .toList(),
        );
  }

  Future<int> addComment({
    required int taskId,
    required int authorId,
    required String body,
  }) {
    final text = Validators.comment(body);
    return guardDb(
      () => _db.transaction(() async {
        final task = await (_db.select(_db.tasks)
              ..where((t) => t.id.equals(taskId) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (task == null) {
          throw const NotFoundException('Задача не найдена');
        }
        return _db.into(_db.comments).insert(
              CommentsCompanion.insert(
                taskId: taskId,
                authorId: Value(authorId),
                body: text,
                createdAt: _now(),
              ),
            );
      }),
    );
  }

  /// Удалять комментарий может только его автор.
  Future<void> deleteComment({required int id, required int actorId}) =>
      guardDb(
        () => _db.transaction(() async {
          final comment = await (_db.select(_db.comments)
                ..where((c) => c.id.equals(id)))
              .getSingleOrNull();
          if (comment == null) {
            throw const NotFoundException('Комментарий не найден');
          }
          if (comment.authorId != actorId) {
            throw const RuleViolationException(
              'Удалить комментарий может только его автор',
            );
          }
          await (_db.delete(_db.comments)..where((c) => c.id.equals(id))).go();
        }),
      );
}
