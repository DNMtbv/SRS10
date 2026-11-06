import 'package:drift/drift.dart';

import '../core/clock.dart';
import '../database/app_database.dart';
import '../models/enums.dart';
import '../models/views.dart';

/// Статистика считается запросами к SQLite, а не в Dart.
/// Задачи из корзины не учитываются ни в одном запросе.
class StatsRepository {
  StatsRepository(this._db, {Clock clock = systemClock}) : _now = clock;

  final AppDatabase _db;
  final Clock _now;

  Stream<DashboardSummary> watchSummary() {
    final today = startOfDay(_now());
    return _db
        .customSelect(
          '''
          SELECT
            (SELECT COUNT(*) FROM projects) AS projects,
            COUNT(*) AS tasks,
            COALESCE(SUM(status = 'done'), 0) AS done,
            COALESCE(SUM(status IN ('todo', 'inProgress')), 0) AS open,
            COALESCE(SUM(status = 'cancelled'), 0) AS cancelled,
            COALESCE(SUM(status IN ('todo', 'inProgress') AND deadline < ?), 0)
              AS overdue
          FROM tasks
          WHERE deleted_at IS NULL
          ''',
          variables: [Variable.withDateTime(today)],
          readsFrom: {_db.tasks, _db.projects},
        )
        .watchSingle()
        .map(
          (r) => DashboardSummary(
            projects: r.read<int>('projects'),
            tasks: r.read<int>('tasks'),
            done: r.read<int>('done'),
            open: r.read<int>('open'),
            cancelled: r.read<int>('cancelled'),
            overdue: r.read<int>('overdue'),
          ),
        );
  }

  /// В результате есть все приоритеты, даже если задач с ними нет.
  Stream<Map<TaskPriority, int>> watchByPriority() => _db
      .customSelect(
        '''
        SELECT priority, COUNT(*) AS total
        FROM tasks
        WHERE deleted_at IS NULL
        GROUP BY priority
        ''',
        readsFrom: {_db.tasks},
      )
      .watch()
      .map((rows) {
        final byName = {
          for (final r in rows) r.read<String>('priority'): r.read<int>('total'),
        };
        return {
          for (final p in TaskPriority.values) p: byName[p.name] ?? 0,
        };
      });

  Stream<List<AssigneeLoad>> watchByAssignee() => _db
      .customSelect(
        '''
        SELECT u.name AS name, COUNT(t.id) AS total
        FROM users u
        LEFT JOIN tasks t ON t.assignee_id = u.id AND t.deleted_at IS NULL
        GROUP BY u.id
        ORDER BY total DESC, u.name
        ''',
        readsFrom: {_db.users, _db.tasks},
      )
      .watch()
      .map(
        (rows) => rows
            .map(
              (r) => AssigneeLoad(
                name: r.read<String>('name'),
                tasks: r.read<int>('total'),
              ),
            )
            .toList(),
      );

  /// Отменённые задачи не входят в процент: их уже не нужно выполнять.
  Stream<List<ProjectProgress>> watchProjectProgress() => _db
      .customSelect(
        '''
        SELECT
          p.id AS id,
          p.name AS name,
          COUNT(t.id) AS total,
          COALESCE(SUM(t.status = 'done'), 0) AS done
        FROM projects p
        LEFT JOIN tasks t
          ON t.project_id = p.id
          AND t.deleted_at IS NULL
          AND t.status != 'cancelled'
        GROUP BY p.id
        ORDER BY p.name
        ''',
        readsFrom: {_db.projects, _db.tasks},
      )
      .watch()
      .map(
        (rows) => rows
            .map(
              (r) => ProjectProgress(
                projectId: r.read<int>('id'),
                name: r.read<String>('name'),
                done: r.read<int>('done'),
                total: r.read<int>('total'),
              ),
            )
            .toList(),
      );
}
