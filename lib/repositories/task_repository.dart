import 'package:drift/drift.dart';

import '../core/app_exception.dart';
import '../core/clock.dart';
import '../core/validators.dart';
import '../database/app_database.dart';
import '../models/entities.dart';
import '../models/enums.dart';
import '../models/views.dart';

class TaskRepository {
  TaskRepository(this._db, {Clock clock = systemClock}) : _now = clock;

  /// Больше стольких незавершённых задач на один дедлайн назначить нельзя.
  static const maxOpenTasksPerDay = 3;

  final AppDatabase _db;
  final Clock _now;

  // ---------- Чтение ----------

  Stream<List<TaskView>> watchTasks(
    TaskFilter filter, {
    required int limit,
    int offset = 0,
  }) {
    final (query, assignee) = _listQuery(filter);
    query.limit(limit, offset: offset);
    return query
        .watch()
        .map((rows) => rows.map((r) => _toView(r, assignee)).toList());
  }

  Future<List<TaskView>> getTasksPage(
    TaskFilter filter, {
    required int limit,
    int offset = 0,
  }) async {
    final (query, assignee) = _listQuery(filter);
    query.limit(limit, offset: offset);
    final rows = await query.get();
    return rows.map((r) => _toView(r, assignee)).toList();
  }

  Stream<TaskView?> watchTask(int id) {
    final (query, assignee) = _baseQuery();
    query.where(_db.tasks.id.equals(id));
    return query.watchSingleOrNull().map(
          (row) => row == null ? null : _toView(row, assignee),
        );
  }

  /// Содержимое корзины: последние удалённые сверху.
  Stream<List<TaskView>> watchTrash() {
    final (query, assignee) = _baseQuery();
    query
      ..where(_db.tasks.deletedAt.isNotNull())
      ..orderBy([OrderingTerm.desc(_db.tasks.deletedAt)]);
    return query
        .watch()
        .map((rows) => rows.map((r) => _toView(r, assignee)).toList());
  }

  Stream<List<HistoryView>> watchHistory(int taskId) {
    final actor = _db.alias(_db.users, 'actor');
    final oldUser = _db.alias(_db.users, 'old_user');
    final newUser = _db.alias(_db.users, 'new_user');
    final history = _db.taskHistory;
    final query = _db.select(history).join([
      leftOuterJoin(actor, actor.id.equalsExp(history.changedBy)),
      leftOuterJoin(oldUser, oldUser.id.equalsExp(history.oldAssigneeId)),
      leftOuterJoin(newUser, newUser.id.equalsExp(history.newAssigneeId)),
    ])
      ..where(history.taskId.equals(taskId))
      ..orderBy([OrderingTerm.desc(history.id)]);
    return query.watch().map(
          (rows) => rows
              .map(
                (r) => HistoryView(
                  entry: r.readTable(history),
                  actorName: r.readTableOrNull(actor)?.name,
                  oldAssigneeName: r.readTableOrNull(oldUser)?.name,
                  newAssigneeName: r.readTableOrNull(newUser)?.name,
                ),
              )
              .toList(),
        );
  }

  /// Отменить можно изменение статуса, если оно ещё не отменено.
  static bool canUndo(List<HistoryView> newestFirst) {
    for (final item in newestFirst) {
      final event = item.entry.event;
      if (event == HistoryEvent.statusChanged) return true;
      if (event == HistoryEvent.statusUndone) return false;
    }
    return false;
  }

  /// Запрос через БД, а не по загруженному списку (задание 3).
  Future<int> openTasksOnDay(int userId, DateTime day, {int? exceptTaskId}) async {
    final start = startOfDay(day);
    final end = DateTime(start.year, start.month, start.day + 1);
    final count = _db.tasks.id.count();
    var where = _db.tasks.assigneeId.equals(userId) &
        _db.tasks.deletedAt.isNull() &
        _db.tasks.deadline.isBiggerOrEqualValue(start) &
        _db.tasks.deadline.isSmallerThanValue(end) &
        _db.tasks.status.isIn([
          TaskStatus.todo.name,
          TaskStatus.inProgress.name,
        ]);
    if (exceptTaskId != null) {
      where = where & _db.tasks.id.equals(exceptTaskId).not();
    }
    final query = _db.selectOnly(_db.tasks)
      ..addColumns([count])
      ..where(where);
    return (await query.getSingle()).read(count)!;
  }

  // ---------- Запись ----------

  /// Задача и первая запись истории сохраняются в одной транзакции: если
  /// история не записалась, задача тоже не появится.
  Future<int> createTask({
    required String title,
    required int projectId,
    required int assigneeId,
    required DateTime deadline,
    required int actorId,
    String description = '',
    TaskPriority priority = TaskPriority.medium,
  }) {
    final cleanTitle = Validators.title(title);
    final cleanDescription = description.trim();
    final day = startOfDay(deadline);
    return guardDb(
      () => _db.transaction(() async {
        await _ensureProjectExists(projectId);
        await _ensureMember(projectId, assigneeId);
        await _ensureDailyLimit(assigneeId, day);
        final now = _now();
        final id = await _db.into(_db.tasks).insert(
              TasksCompanion.insert(
                title: cleanTitle,
                description: Value(cleanDescription),
                searchText: Value(_searchText(cleanTitle, cleanDescription)),
                projectId: projectId,
                assigneeId: Value(assigneeId),
                priority: Value(priority),
                status: TaskStatus.todo,
                deadline: day,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _addHistory(
          taskId: id,
          event: HistoryEvent.created,
          newStatus: TaskStatus.todo,
          newAssigneeId: assigneeId,
          actorId: actorId,
          at: now,
        );
        return id;
      }),
    );
  }

  Future<void> updateTask({
    required int id,
    required String title,
    required String description,
    required TaskPriority priority,
    required DateTime deadline,
  }) {
    final cleanTitle = Validators.title(title);
    final cleanDescription = description.trim();
    final day = startOfDay(deadline);
    return guardDb(
      () => _db.transaction(() async {
        final task = await _requireActiveTask(id);
        final assignee = task.assigneeId;
        if (assignee != null && task.status.isOpen && task.deadline != day) {
          await _ensureDailyLimit(assignee, day, exceptTaskId: id);
        }
        await _write(
          id,
          TasksCompanion(
            title: Value(cleanTitle),
            description: Value(cleanDescription),
            searchText: Value(_searchText(cleanTitle, cleanDescription)),
            priority: Value(priority),
            deadline: Value(day),
            updatedAt: Value(_now()),
          ),
        );
      }),
    );
  }

  Future<void> changePriority(int id, TaskPriority priority) => guardDb(
        () => _db.transaction(() async {
          await _requireActiveTask(id);
          await _write(
            id,
            TasksCompanion(
              priority: Value(priority),
              updatedAt: Value(_now()),
            ),
          );
        }),
      );

  /// Статус и запись истории меняются вместе.
  Future<void> changeStatus({
    required int id,
    required TaskStatus status,
    required int actorId,
  }) =>
      guardDb(
        () => _db.transaction(() async {
          final task = await _requireActiveTask(id);
          if (task.status == status) return;
          await _setStatus(
            task: task,
            status: status,
            event: HistoryEvent.statusChanged,
            actorId: actorId,
          );
        }),
      );

  /// Возвращает статус, который был до последнего изменения. Сама отмена тоже
  /// попадает в историю, поэтому история остаётся полной.
  Future<void> undoLastStatusChange({
    required int id,
    required int actorId,
  }) =>
      guardDb(
        () => _db.transaction(() async {
          final task = await _requireActiveTask(id);
          final last = await (_db.select(_db.taskHistory)
                ..where(
                  (h) =>
                      h.taskId.equals(id) &
                      h.event.isIn([
                        HistoryEvent.statusChanged.name,
                        HistoryEvent.statusUndone.name,
                      ]),
                )
                ..orderBy([(h) => OrderingTerm.desc(h.id)])
                ..limit(1))
              .getSingleOrNull();
          final previous = last?.oldStatus;
          if (last == null ||
              last.event != HistoryEvent.statusChanged ||
              previous == null) {
            throw const RuleViolationException('Нет изменений для отмены');
          }
          await _setStatus(
            task: task,
            status: previous,
            event: HistoryEvent.statusUndone,
            actorId: actorId,
          );
        }),
      );

  /// Проверка участия, смена исполнителя и запись в историю — одна транзакция.
  Future<void> reassign({
    required int id,
    required int assigneeId,
    required int actorId,
  }) =>
      guardDb(
        () => _db.transaction(() async {
          final task = await _requireActiveTask(id);
          if (task.assigneeId == assigneeId) return;
          await _ensureMember(task.projectId, assigneeId);
          if (task.status.isOpen) {
            await _ensureDailyLimit(assigneeId, task.deadline);
          }
          final now = _now();
          await _write(
            id,
            TasksCompanion(
              assigneeId: Value(assigneeId),
              updatedAt: Value(now),
            ),
          );
          await _addHistory(
            taskId: id,
            event: HistoryEvent.reassigned,
            oldAssigneeId: task.assigneeId,
            newAssigneeId: assigneeId,
            actorId: actorId,
            at: now,
          );
        }),
      );

  /// Soft Delete: задача остаётся в базе и попадает в корзину.
  Future<void> moveToTrash(int id) => guardDb(
        () => _db.transaction(() async {
          await _requireActiveTask(id);
          await _write(id, TasksCompanion(deletedAt: Value(_now())));
        }),
      );

  Future<void> restore(int id) => guardDb(() async {
        final changed = await (_db.update(_db.tasks)
              ..where((t) => t.id.equals(id) & t.deletedAt.isNotNull()))
            .write(const TasksCompanion(deletedAt: Value(null)));
        if (changed == 0) {
          throw const NotFoundException('Задача не найдена в корзине');
        }
      });

  /// Полное удаление: комментарии, вложения и история удаляются каскадно.
  Future<void> deletePermanently(int id) => guardDb(() async {
        final deleted = await (_db.delete(_db.tasks)
              ..where((t) => t.id.equals(id) & t.deletedAt.isNotNull()))
            .go();
        if (deleted == 0) {
          throw const NotFoundException('Задача не найдена в корзине');
        }
      });

  // ---------- Внутреннее ----------

  (JoinedSelectStatement<HasResultSet, dynamic>, $UsersTable) _baseQuery() {
    final assignee = _db.alias(_db.users, 'assignee');
    // project_id обязателен, поэтому LEFT JOIN вернёт те же строки, что и INNER.
    // Зато SQLite обязан читать сначала tasks: иначе он может начать с projects
    // и потерять готовый порядок индекса, тогда сортировка станет медленнее.
    final query = _db.select(_db.tasks).join([
      leftOuterJoin(
        _db.projects,
        _db.projects.id.equalsExp(_db.tasks.projectId),
      ),
      leftOuterJoin(assignee, assignee.id.equalsExp(_db.tasks.assigneeId)),
    ]);
    return (query, assignee);
  }

  (JoinedSelectStatement<HasResultSet, dynamic>, $UsersTable) _listQuery(
    TaskFilter f,
  ) {
    final (query, assignee) = _baseQuery();
    final tasks = _db.tasks;

    Expression<bool> where = tasks.deletedAt.isNull();
    if (f.projectId != null) where &= tasks.projectId.equals(f.projectId!);
    if (f.assigneeId != null) where &= tasks.assigneeId.equals(f.assigneeId!);
    if (f.status != null) where &= tasks.status.equals(f.status!.name);
    if (f.priority != null) where &= tasks.priority.equals(f.priority!.name);

    // SQLite не приводит кириллицу к нижнему регистру (LIKE и lower() работают
    // только с ASCII), поэтому поиск идёт по заранее подготовленному полю.
    final text = f.query.trim().toLowerCase();
    if (text.isNotEmpty) {
      where &= FunctionCallExpression<int>('instr', [
        tasks.searchText,
        Variable<String>(text),
      ]).isBiggerThanValue(0);
    }

    // Второй ключ id нужен, чтобы при равных датах страницы не перемешивались.
    // Его направление совпадает с первым: так SQLite читает готовый порядок
    // из индекса и не сортирует строки заново.
    final order = switch (f.sort) {
      TaskSort.createdDesc => [
          OrderingTerm.desc(tasks.createdAt),
          OrderingTerm.desc(tasks.id),
        ],
      TaskSort.createdAsc => [
          OrderingTerm.asc(tasks.createdAt),
          OrderingTerm.asc(tasks.id),
        ],
      TaskSort.deadlineAsc => [
          OrderingTerm.asc(tasks.deadline),
          OrderingTerm.asc(tasks.id),
        ],
      TaskSort.deadlineDesc => [
          OrderingTerm.desc(tasks.deadline),
          OrderingTerm.desc(tasks.id),
        ],
    };
    query
      ..where(where)
      ..orderBy(order);
    return (query, assignee);
  }

  TaskView _toView(TypedResult row, $UsersTable assignee) => TaskView(
        task: row.readTable(_db.tasks),
        projectName: row.readTable(_db.projects).name,
        assigneeName: row.readTableOrNull(assignee)?.name,
      );

  Future<void> _setStatus({
    required Task task,
    required TaskStatus status,
    required HistoryEvent event,
    required int actorId,
  }) async {
    final now = _now();
    await _write(
      task.id,
      TasksCompanion(status: Value(status), updatedAt: Value(now)),
    );
    await _addHistory(
      taskId: task.id,
      event: event,
      oldStatus: task.status,
      newStatus: status,
      actorId: actorId,
      at: now,
    );
  }

  Future<void> _write(int id, TasksCompanion values) =>
      (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(values);

  Future<void> _addHistory({
    required int taskId,
    required HistoryEvent event,
    required int actorId,
    required DateTime at,
    TaskStatus? oldStatus,
    TaskStatus? newStatus,
    int? oldAssigneeId,
    int? newAssigneeId,
  }) =>
      _db.into(_db.taskHistory).insert(
            TaskHistoryCompanion.insert(
              taskId: taskId,
              event: event,
              oldStatus: Value(oldStatus),
              newStatus: Value(newStatus),
              oldAssigneeId: Value(oldAssigneeId),
              newAssigneeId: Value(newAssigneeId),
              changedBy: Value(actorId),
              changedAt: at,
            ),
          );

  Future<Task> _requireActiveTask(int id) async {
    final task = await (_db.select(_db.tasks)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (task == null) throw const NotFoundException('Задача не найдена');
    return task;
  }

  Future<void> _ensureProjectExists(int projectId) async {
    final project = await (_db.select(_db.projects)
          ..where((p) => p.id.equals(projectId)))
        .getSingleOrNull();
    if (project == null) {
      throw const NotFoundException('Проект не найден');
    }
  }

  Future<void> _ensureMember(int projectId, int userId) async {
    final member = await (_db.select(_db.projectMembers)
          ..where(
            (m) => m.projectId.equals(projectId) & m.userId.equals(userId),
          ))
        .getSingleOrNull();
    if (member == null) {
      throw const RuleViolationException(
        'Исполнителем может быть только участник проекта',
      );
    }
  }

  Future<void> _ensureDailyLimit(
    int userId,
    DateTime day, {
    int? exceptTaskId,
  }) async {
    final count = await openTasksOnDay(userId, day, exceptTaskId: exceptTaskId);
    if (count >= maxOpenTasksPerDay) {
      throw const RuleViolationException(
        'На эту дату у исполнителя уже $maxOpenTasksPerDay незавершённые задачи',
      );
    }
  }

  static String _searchText(String title, String description) =>
      '$title\n$description'.toLowerCase();
}
