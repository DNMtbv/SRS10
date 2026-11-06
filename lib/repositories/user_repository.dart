import 'package:drift/drift.dart';

import '../core/app_exception.dart';
import '../core/clock.dart';
import '../core/validators.dart';
import '../database/app_database.dart';
import '../models/entities.dart';
import '../models/enums.dart';

class UserRepository {
  UserRepository(this._db, {Clock clock = systemClock}) : _now = clock;

  static const _currentUserKey = 'current_user_id';

  final AppDatabase _db;
  final Clock _now;

  Stream<List<User>> watchUsers() =>
      (_db.select(_db.users)..orderBy([(u) => OrderingTerm.asc(u.name)]))
          .watch();

  Stream<User?> watchUser(int id) =>
      (_db.select(_db.users)..where((u) => u.id.equals(id)))
          .watchSingleOrNull();

  Future<int> createUser({required String name, required String email}) {
    final cleanName = Validators.name(name);
    final cleanEmail = Validators.email(email);
    return guardDb(() async {
      await _ensureEmailFree(cleanEmail);
      return _db.into(_db.users).insert(
            UsersCompanion.insert(
              name: cleanName,
              email: cleanEmail,
              registeredAt: _now(),
            ),
          );
    });
  }

  Future<void> updateUser({
    required int id,
    required String name,
    required String email,
  }) {
    final cleanName = Validators.name(name);
    final cleanEmail = Validators.email(email);
    return guardDb(() async {
      await _ensureEmailFree(cleanEmail, exceptId: id);
      final changed =
          await (_db.update(_db.users)..where((u) => u.id.equals(id))).write(
        UsersCompanion(name: Value(cleanName), email: Value(cleanEmail)),
      );
      if (changed == 0) {
        throw const NotFoundException('Пользователь не найден');
      }
    });
  }

  /// Участие в проектах удаляется каскадно, а в завершённых задачах, истории
  /// и комментариях ссылка на пользователя становится пустой.
  Future<void> deleteUser(int id) => guardDb(
        () => _db.transaction(() async {
          final open = await openTaskCount(id);
          if (open > 0) {
            throw RuleViolationException(
              'Нельзя удалить пользователя: незавершённых задач — $open',
            );
          }
          final deleted = await (_db.delete(_db.users)
                ..where((u) => u.id.equals(id)))
              .go();
          if (deleted == 0) {
            throw const NotFoundException('Пользователь не найден');
          }
        }),
      );

  /// Незавершённые задачи вне корзины.
  Future<int> openTaskCount(int userId) async {
    final count = _db.tasks.id.count();
    final query = _db.selectOnly(_db.tasks)
      ..addColumns([count])
      ..where(
        _db.tasks.assigneeId.equals(userId) &
            _db.tasks.deletedAt.isNull() &
            _db.tasks.status.isIn([
              TaskStatus.todo.name,
              TaskStatus.inProgress.name,
            ]),
      );
    return (await query.getSingle()).read(count)!;
  }

  Stream<int?> watchCurrentUserId() {
    final query = _db.select(_db.appSettings)
      ..where((s) => s.key.equals(_currentUserKey));
    return query
        .watchSingleOrNull()
        .map((row) => row == null ? null : int.tryParse(row.value));
  }

  Future<void> setCurrentUser(int? userId) async {
    if (userId == null) {
      await (_db.delete(_db.appSettings)
            ..where((s) => s.key.equals(_currentUserKey)))
          .go();
      return;
    }
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _currentUserKey,
            value: '$userId',
          ),
        );
  }

  Future<void> _ensureEmailFree(String email, {int? exceptId}) async {
    final query = _db.select(_db.users)..where((u) => u.email.equals(email));
    final existing = await query.getSingleOrNull();
    if (existing != null && existing.id != exceptId) {
      throw const RuleViolationException(
        'Пользователь с таким email уже существует',
      );
    }
  }
}
