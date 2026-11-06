import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../core/clock.dart';
import '../database/app_database.dart';
import '../models/enums.dart';
import '../models/views.dart';
import 'attachment_repository.dart';
import 'comment_repository.dart';
import 'project_repository.dart';
import 'task_repository.dart';
import 'user_repository.dart';

/// Тестовые данные, очистка базы и сравнение скорости запросов.
class MaintenanceRepository {
  MaintenanceRepository(
    this._db, {
    required this.attachments,
    required this._temporaryDirectory,
    Clock clock = systemClock,
  }) : _now = clock;

  final AppDatabase _db;
  final AttachmentRepository attachments;
  final Future<Directory> Function() _temporaryDirectory;
  final Clock _now;

  /// Небольшой набор для знакомства с приложением. Идёт через обычные
  /// репозитории, поэтому история и проверки работают как при ручном вводе.
  Future<void> seedDemo() async {
    final tag = _now().millisecondsSinceEpoch;
    final users = UserRepository(_db, clock: _now);
    final projects = ProjectRepository(_db, clock: _now);
    final tasks = TaskRepository(_db, clock: _now);
    final comments = CommentRepository(_db, clock: _now);

    final anna = await users.createUser(
      name: 'Анна Ким',
      email: 'anna.$tag@taskflow.kz',
    );
    final boris = await users.createUser(
      name: 'Борис Ли',
      email: 'boris.$tag@taskflow.kz',
    );
    final dana = await users.createUser(
      name: 'Дана Серик',
      email: 'dana.$tag@taskflow.kz',
    );

    final site = await projects.createProject(
      name: 'Сайт колледжа',
      description: 'Новая версия сайта',
      ownerId: anna,
    );
    await projects.addMember(
      projectId: site,
      userId: boris,
      role: ProjectRole.admin,
    );
    await projects.addMember(projectId: site, userId: dana);
    final app = await projects.createProject(
      name: 'Мобильное приложение',
      description: 'Приложение для студентов',
      ownerId: boris,
    );
    await projects.addMember(projectId: app, userId: dana);

    final today = startOfDay(_now());
    DateTime inDays(int days) =>
        DateTime(today.year, today.month, today.day + days);

    final design = await tasks.createTask(
      title: 'Согласовать дизайн',
      description: 'Макеты главной страницы',
      projectId: site,
      assigneeId: boris,
      priority: TaskPriority.high,
      deadline: inDays(2),
      actorId: anna,
    );
    await tasks.changeStatus(
      id: design,
      status: TaskStatus.inProgress,
      actorId: boris,
    );
    await comments.addComment(
      taskId: design,
      authorId: anna,
      body: 'Макеты жду к пятнице',
    );

    final hosting = await tasks.createTask(
      title: 'Оплатить хостинг',
      projectId: site,
      assigneeId: anna,
      priority: TaskPriority.critical,
      deadline: inDays(-1),
      actorId: anna,
    );
    await tasks.createTask(
      title: 'Написать тексты',
      projectId: site,
      assigneeId: dana,
      priority: TaskPriority.low,
      deadline: inDays(7),
      actorId: anna,
    );
    await tasks.changeStatus(
      id: hosting,
      status: TaskStatus.inProgress,
      actorId: anna,
    );

    final login = await tasks.createTask(
      title: 'Экран входа',
      description: 'Форма входа и восстановление пароля',
      projectId: app,
      assigneeId: dana,
      priority: TaskPriority.high,
      deadline: inDays(3),
      actorId: boris,
    );
    await tasks.changeStatus(
      id: login,
      status: TaskStatus.done,
      actorId: dana,
    );
    await tasks.createTask(
      title: 'Настроить уведомления',
      projectId: app,
      assigneeId: boris,
      deadline: inDays(10),
      actorId: boris,
    );

    await users.setCurrentUser(anna);
  }

  /// Быстрая загрузка большого объёма одной транзакцией. Проверки репозиториев
  /// здесь намеренно обходятся: важен только объём данных.
  Future<void> seedLarge({
    int users = 1000,
    int projects = 100,
    int tasks = 10000,
    int membersPerProject = 10,
  }) async {
    final random = Random(42);
    final now = _now();
    final tag = now.millisecondsSinceEpoch;
    final today = startOfDay(now);

    final userBase = await _maxId('users');
    final projectBase = await _maxId('projects');
    final taskBase = await _maxId('tasks');

    final membersOf = <int, List<int>>{};
    for (var i = 1; i <= projects; i++) {
      final projectId = projectBase + i;
      final picked = <int>{};
      while (picked.length < min(membersPerProject, users)) {
        picked.add(userBase + 1 + random.nextInt(users));
      }
      membersOf[projectId] = picked.toList();
    }

    await _db.transaction(() async {
      await _db.batch((b) {
        b.insertAll(_db.users, [
          for (var i = 1; i <= users; i++)
            UsersCompanion.insert(
              id: Value(userBase + i),
              name: 'Пользователь $i',
              email: 'user$i.$tag@taskflow.test',
              registeredAt: now,
            ),
        ]);
        b.insertAll(_db.projects, [
          for (var i = 1; i <= projects; i++)
            ProjectsCompanion.insert(
              id: Value(projectBase + i),
              name: 'Проект $i',
              createdAt: now,
              status: ProjectStatus.active,
            ),
        ]);
        b.insertAll(_db.projectMembers, [
          for (final entry in membersOf.entries)
            for (final (index, userId) in entry.value.indexed)
              ProjectMembersCompanion.insert(
                projectId: entry.key,
                userId: userId,
                role: index == 0 ? ProjectRole.owner : ProjectRole.member,
                joinedAt: now,
              ),
        ]);
      });

      final statuses = TaskStatus.values;
      final priorities = TaskPriority.values;
      await _db.batch((b) {
        for (var i = 1; i <= tasks; i++) {
          final id = taskBase + i;
          final projectId = projectBase + 1 + random.nextInt(projects);
          final members = membersOf[projectId]!;
          final assignee = members[random.nextInt(members.length)];
          final title = 'Задача $i';
          final description = 'Описание задачи номер $i';
          final created = now.subtract(Duration(minutes: i));
          final status = statuses[random.nextInt(statuses.length)];
          b.insert(
            _db.tasks,
            TasksCompanion.insert(
              id: Value(id),
              title: title,
              description: Value(description),
              searchText: Value('$title\n$description'.toLowerCase()),
              projectId: projectId,
              assigneeId: Value(assignee),
              priority: Value(priorities[random.nextInt(priorities.length)]),
              status: status,
              deadline: DateTime(
                today.year,
                today.month,
                today.day + random.nextInt(365) - 180,
              ),
              createdAt: created,
              updatedAt: created,
            ),
          );
          b.insert(
            _db.taskHistory,
            TaskHistoryCompanion.insert(
              taskId: id,
              event: HistoryEvent.created,
              newStatus: Value(status),
              newAssigneeId: Value(assignee),
              changedBy: Value(assignee),
              changedAt: created,
            ),
          );
        }
      });
    });
  }

  /// Удаляет все записи и сохранённые файлы вложений.
  Future<void> clearAll() async {
    final rows = await _db.select(_db.attachments).get();
    await _db.transaction(() async {
      await _db.delete(_db.projects).go();
      await _db.delete(_db.users).go();
      await _db.delete(_db.appSettings).go();
    });
    await attachments.deleteFiles(rows.map((a) => a.filePath));
  }

  Future<int> _maxId(String table) async {
    final row = await _db
        .customSelect('SELECT COALESCE(MAX(id), 0) AS id FROM $table')
        .getSingle();
    return row.read<int>('id');
  }

  /// Сравнение идёт на отдельной временной базе: рабочие данные не меняются,
  /// а индексы удаляются только там.
  Future<List<BenchmarkRow>> runBenchmark({
    int users = 1000,
    int projects = 100,
    int tasks = 10000,
    int repeats = 20,
  }) async {
    final directory = await _temporaryDirectory();
    await directory.create(recursive: true);
    final file = File(
      p.join(directory.path, 'benchmark_${_now().millisecondsSinceEpoch}.db'),
    );
    final bench = AppDatabase(NativeDatabase.createInBackground(file));
    try {
      final seeder = MaintenanceRepository(
        bench,
        attachments: attachments,
        temporaryDirectory: _temporaryDirectory,
        clock: _now,
      );
      await seeder.seedLarge(users: users, projects: projects, tasks: tasks);
      return await compareIndexes(bench, repeats: repeats, clock: _now);
    } finally {
      await bench.close();
      for (final path in [file.path, '${file.path}-wal', '${file.path}-shm']) {
        final part = File(path);
        if (part.existsSync()) await part.delete();
      }
    }
  }

  /// Замеряет запросы с индексами, удаляет индексы таблицы tasks и повторяет.
  /// База [db] после этого остаётся без индексов, поэтому она должна быть
  /// временной.
  static Future<List<BenchmarkRow>> compareIndexes(
    AppDatabase db, {
    int repeats = 20,
    Clock clock = systemClock,
  }) async {
    final queries = _benchmarkQueries(clock());
    await db.customStatement('ANALYZE');

    Future<(double, String)> measure(_BenchmarkQuery q) async {
      final plan = await db
          .customSelect('EXPLAIN QUERY PLAN ${q.sql}', variables: q.variables)
          .get();
      final detail = plan.map((r) => r.read<String>('detail')).join('; ');
      final watch = Stopwatch()..start();
      for (var i = 0; i < repeats; i++) {
        await db.customSelect(q.sql, variables: q.variables).get();
      }
      watch.stop();
      return (watch.elapsedMicroseconds / repeats / 1000, detail);
    }

    final withIndex = [for (final q in queries) await measure(q)];

    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'index' AND name LIKE 'idx_tasks_%'",
        )
        .get();
    for (final row in indexes) {
      await db.customStatement('DROP INDEX ${row.read<String>('name')}');
    }
    await db.customStatement('ANALYZE');

    final withoutIndex = [for (final q in queries) await measure(q)];

    return [
      for (var i = 0; i < queries.length; i++)
        BenchmarkRow(
          name: queries[i].name,
          withIndexMs: withIndex[i].$1,
          withoutIndexMs: withoutIndex[i].$1,
          planWithIndex: withIndex[i].$2,
          planWithoutIndex: withoutIndex[i].$2,
        ),
    ];
  }

  static List<_BenchmarkQuery> _benchmarkQueries(DateTime now) {
    final today = startOfDay(now);
    final seconds = today.millisecondsSinceEpoch ~/ 1000;
    const list = '''
      SELECT t.id, t.title FROM tasks t
      LEFT JOIN projects p ON p.id = t.project_id
      LEFT JOIN users u ON u.id = t.assignee_id
    ''';
    return [
      _BenchmarkQuery(
        'Список: новые сверху, страница 1',
        '$list WHERE t.deleted_at IS NULL '
            'ORDER BY t.created_at DESC, t.id DESC LIMIT 20',
      ),
      _BenchmarkQuery(
        'Пагинация: OFFSET 5000',
        '$list WHERE t.deleted_at IS NULL '
            'ORDER BY t.created_at DESC, t.id DESC LIMIT 20 OFFSET 5000',
      ),
      _BenchmarkQuery(
        'Сортировка по дедлайну',
        '$list WHERE t.deleted_at IS NULL '
            'ORDER BY t.deadline ASC, t.id ASC LIMIT 20',
      ),
      _BenchmarkQuery(
        'Фильтр по статусу',
        "$list WHERE t.deleted_at IS NULL AND t.status = 'inProgress' "
            'ORDER BY t.created_at DESC, t.id DESC LIMIT 20',
      ),
      _BenchmarkQuery(
        'Фильтр по приоритету',
        "$list WHERE t.deleted_at IS NULL AND t.priority = 'critical' "
            'ORDER BY t.created_at DESC, t.id DESC LIMIT 20',
      ),
      _BenchmarkQuery(
        'Задачи проекта',
        '$list WHERE t.deleted_at IS NULL AND t.project_id = 1 '
            'ORDER BY t.created_at DESC, t.id DESC LIMIT 20',
      ),
      _BenchmarkQuery(
        'Лимит 3 задачи на дату',
        'SELECT COUNT(*) FROM tasks WHERE assignee_id = 1 '
            'AND deleted_at IS NULL AND deadline >= ? AND deadline < ? '
            "AND status IN ('todo', 'inProgress')",
        [
          Variable.withInt(seconds),
          Variable.withInt(seconds + 86400),
        ],
      ),
      _BenchmarkQuery(
        'Просроченные задачи',
        'SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL AND deadline < ? '
            "AND status IN ('todo', 'inProgress')",
        [Variable.withInt(seconds)],
      ),
      _BenchmarkQuery(
        'Поиск по тексту',
        "$list WHERE t.deleted_at IS NULL AND instr(t.search_text, 'задача 9999') > 0 "
            'ORDER BY t.created_at DESC, t.id DESC LIMIT 20',
      ),
    ];
  }
}

class _BenchmarkQuery {
  const _BenchmarkQuery(this.name, this.sql, [this.variables = const []]);

  final String name;
  final String sql;
  final List<Variable<Object>> variables;
}
