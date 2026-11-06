import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:taskflow/database/app_database.dart';
import 'package:taskflow/models/enums.dart';
import 'package:taskflow/models/views.dart';
import 'package:taskflow/repositories/task_repository.dart';

import 'helpers/world.dart';

/// Таблица tasks первой версии приложения: поля priority ещё нет.
const _tasksV1 = '''
CREATE TABLE tasks (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  search_text TEXT NOT NULL DEFAULT '',
  project_id INTEGER NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  assignee_id INTEGER NULL REFERENCES users (id) ON DELETE SET NULL,
  status TEXT NOT NULL,
  deadline INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER NULL
)
''';

/// Схема версии 1: все объекты текущей схемы, кроме tasks и индекса priority.
Future<List<String>> _schemaV1() async {
  final fresh = memoryDatabase();
  final rows = await fresh
      .customSelect(
        "SELECT name, type, sql FROM sqlite_master WHERE sql IS NOT NULL "
        "AND name NOT LIKE 'sqlite_%' "
        "AND name NOT IN ('tasks', 'idx_tasks_priority_created') "
        "ORDER BY type DESC",
      )
      .get();
  await fresh.close();
  return [_tasksV1, ...rows.map((r) => r.read<String>('sql'))];
}

void _fillV1(Database raw) {
  raw.execute('''
    INSERT INTO users (id, name, email, registered_at)
    VALUES (1, 'Анна', 'anna@mail.kz', 1000);
    INSERT INTO projects (id, name, description, created_at, status)
    VALUES (1, 'Сайт', '', 1000, 'active');
    INSERT INTO project_members (project_id, user_id, role, joined_at)
    VALUES (1, 1, 'owner', 1000);
    INSERT INTO tasks
      (id, title, project_id, assignee_id, status, deadline, created_at, updated_at)
    VALUES
      (1, 'Старая задача', 1, 1, 'todo', 2000, 1000, 1000),
      (2, 'Завершённая', 1, 1, 'done', 2000, 1000, 1000);
    INSERT INTO task_history (task_id, event, new_status, changed_by, changed_at)
    VALUES (1, 'created', 'todo', 1, 1000);
  ''');
  raw.userVersion = 1;
}

Future<Set<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

Future<Set<String>> _indexes(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name LIKE 'idx_%'",
      )
      .get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

void main() {
  late List<String> schema;

  setUpAll(() async => schema = await _schemaV1());

  AppDatabase openV1() {
    final raw = sqlite3.openInMemory();
    schema.forEach(raw.execute);
    _fillV1(raw);
    return AppDatabase(NativeDatabase.opened(raw));
  }

  test('тестовая база действительно версии 1, поля priority нет', () {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);
    schema.forEach(raw.execute);
    _fillV1(raw);

    final columns = raw.select('PRAGMA table_info(tasks)');
    expect(columns.map((c) => c['name']), isNot(contains('priority')));
    expect(raw.userVersion, 1);
  });

  test('миграция: старые задачи получают приоритет medium', () async {
    final db = openV1();
    addTearDown(db.close);

    final tasks = await db.select(db.tasks).get();

    expect(tasks, hasLength(2));
    expect(tasks.map((t) => t.priority), everyElement(TaskPriority.medium));
  });

  test('миграция не теряет данные', () async {
    final db = openV1();
    addTearDown(db.close);

    final tasks = await (db.select(db.tasks)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();

    expect(tasks.map((t) => t.title), ['Старая задача', 'Завершённая']);
    expect(tasks.map((t) => t.status), [TaskStatus.todo, TaskStatus.done]);
    expect(await db.select(db.users).get(), hasLength(1));
    expect(await db.select(db.projectMembers).get(), hasLength(1));
    expect(await db.select(db.taskHistory).get(), hasLength(1));
  });

  test('после миграции схема совпадает с новой установкой', () async {
    final migrated = openV1();
    addTearDown(migrated.close);
    final fresh = memoryDatabase();
    addTearDown(fresh.close);
    await migrated.select(migrated.users).get();
    await fresh.select(fresh.users).get();

    expect(await _columns(migrated, 'tasks'), await _columns(fresh, 'tasks'));
    expect(await _indexes(migrated), await _indexes(fresh));
  });

  test('версия базы обновилась до 2', () async {
    final db = openV1();
    addTearDown(db.close);

    final row = await db.customSelect('PRAGMA user_version').getSingle();

    expect(row.read<int>('user_version'), 2);
    expect(db.schemaVersion, 2);
  });

  test('CHECK работает и для перенесённого поля', () async {
    final db = openV1();
    addTearDown(db.close);
    await db.select(db.tasks).get();

    await expectLater(
      db.customStatement("UPDATE tasks SET priority = 'urgent' WHERE id = 1"),
      throwsA(anything),
    );
  });

  test('приложение работает с перенесённой базой', () async {
    final db = openV1();
    addTearDown(db.close);
    final tasks = TaskRepository(db);

    await tasks.changePriority(1, TaskPriority.high);

    final page = await tasks.getTasksPage(
      const TaskFilter(priority: TaskPriority.high),
      limit: 20,
    );
    expect(page.single.task.title, 'Старая задача');
  });

  test('данные и история сохраняются в файле после перезапуска', () async {
    final directory = await Directory.systemTemp.createTemp('taskflow_file');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'taskflow.db'));

    // Первый запуск: файл версии 1.
    final raw = sqlite3.open(file.path);
    schema.forEach(raw.execute);
    _fillV1(raw);
    raw.close();

    // Второй запуск: миграция и новая запись.
    final second = AppDatabase(NativeDatabase(file));
    await TaskRepository(second).changeStatus(
      id: 1,
      status: TaskStatus.inProgress,
      actorId: 1,
    );
    await second.close();

    // Третий запуск: повторной миграции нет, всё на месте.
    final third = AppDatabase(NativeDatabase(file));
    addTearDown(third.close);
    final tasks = TaskRepository(third);
    final view = (await tasks.watchTask(1).first)!;
    final history = await tasks.watchHistory(1).first;

    expect(view.task.status, TaskStatus.inProgress);
    expect(view.task.priority, TaskPriority.medium);
    expect(history, hasLength(2));
  });
}
