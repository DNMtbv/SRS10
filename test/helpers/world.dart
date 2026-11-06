import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/database/app_database.dart';
import 'package:taskflow/repositories/attachment_repository.dart';
import 'package:taskflow/repositories/comment_repository.dart';
import 'package:taskflow/repositories/maintenance_repository.dart';
import 'package:taskflow/repositories/project_repository.dart';
import 'package:taskflow/repositories/stats_repository.dart';
import 'package:taskflow/repositories/task_repository.dart';
import 'package:taskflow/repositories/user_repository.dart';

/// Настоящий SQLite в памяти: проверяются реальные ограничения и транзакции.
AppDatabase memoryDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
  );
}

/// База с двумя участниками проекта и одним посторонним пользователем.
class World {
  World._(this.db, this.files);

  final AppDatabase db;
  final Directory files;

  DateTime now = DateTime(2026, 6, 15, 12);
  DateTime clock() => now;

  late final users = UserRepository(db, clock: clock);
  late final projects = ProjectRepository(db, clock: clock);
  late final tasks = TaskRepository(db, clock: clock);
  late final comments = CommentRepository(db, clock: clock);
  late final stats = StatsRepository(db, clock: clock);
  late final attachments = AttachmentRepository(
    db,
    storageDirectory: () async => files,
    clock: clock,
  );
  late final maintenance = MaintenanceRepository(
    db,
    attachments: attachments,
    temporaryDirectory: () async => files,
    clock: clock,
  );

  late int anna;
  late int boris;
  late int outsider;
  late int project;

  DateTime get deadline => DateTime(2026, 6, 20);

  Future<int> task({
    String title = 'Задача',
    String description = '',
    int? assignee,
    DateTime? deadline,
  }) =>
      tasks.createTask(
        title: title,
        description: description,
        projectId: project,
        assigneeId: assignee ?? boris,
        deadline: deadline ?? this.deadline,
        actorId: anna,
      );

  static Future<World> create() async {
    final files = await Directory.systemTemp.createTemp('taskflow_test');
    final world = World._(memoryDatabase(), files);
    world.anna = await world.users.createUser(
      name: 'Анна Ким',
      email: 'anna@mail.kz',
    );
    world.boris = await world.users.createUser(
      name: 'Борис Ли',
      email: 'boris@mail.kz',
    );
    world.outsider = await world.users.createUser(
      name: 'Посторонний',
      email: 'out@mail.kz',
    );
    world.project = await world.projects.createProject(
      name: 'Сайт',
      ownerId: world.anna,
    );
    await world.projects.addMember(
      projectId: world.project,
      userId: world.boris,
    );
    addTearDown(world.dispose);
    return world;
  }

  Future<void> dispose() async {
    await db.close();
    if (files.existsSync()) await files.delete(recursive: true);
  }
}
