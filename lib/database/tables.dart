// Проверки CHECK ссылаются на собственный столбец: так задумано в Drift.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import '../models/entities.dart';
import '../models/enums.dart';

@UseRowClass(User)
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 2, max: 100)();
  TextColumn get email => text().unique()();
  DateTimeColumn get registeredAt => dateTime()();
}

@UseRowClass(Project)
class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get status => textEnum<ProjectStatus>().check(
        status.isIn(ProjectStatus.values.map((e) => e.name)),
      )();
}

/// Связь Many-to-Many: пользователь ↔ проект. Составной первичный ключ не даёт
/// добавить одного пользователя в проект дважды.
@UseRowClass(ProjectMember)
@TableIndex(name: 'idx_members_user', columns: {#userId})
class ProjectMembers extends Table {
  IntColumn get projectId =>
      integer().references(Projects, #id, onDelete: KeyAction.cascade)();
  IntColumn get userId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => textEnum<ProjectRole>().check(
        role.isIn(ProjectRole.values.map((e) => e.name)),
      )();
  DateTimeColumn get joinedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {projectId, userId};
}

@UseRowClass(Task)
@TableIndex(name: 'idx_tasks_project', columns: {#projectId, #deletedAt})
@TableIndex(name: 'idx_tasks_assignee_deadline', columns: {#assigneeId, #deadline})
@TableIndex(name: 'idx_tasks_status_created', columns: {#status, #createdAt})
@TableIndex(name: 'idx_tasks_priority_created', columns: {#priority, #createdAt})
@TableIndex(name: 'idx_tasks_active_created', columns: {#deletedAt, #createdAt})
@TableIndex(
  name: 'idx_tasks_active_deadline',
  columns: {#deletedAt, #deadline, #status},
)
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get searchText => text().withDefault(const Constant(''))();

  /// NOT NULL + внешний ключ: задача без проекта невозможна даже на уровне БД.
  IntColumn get projectId =>
      integer().references(Projects, #id, onDelete: KeyAction.cascade)();

  /// Становится NULL, если пользователя удалили: завершённые задачи остаются.
  IntColumn get assigneeId => integer()
      .nullable()
      .references(Users, #id, onDelete: KeyAction.setNull)();

  /// Появилось во второй версии схемы (см. миграцию в `AppDatabase`).
  TextColumn get priority => textEnum<TaskPriority>()
      .withDefault(Constant(TaskPriority.medium.name))
      .check(priority.isIn(TaskPriority.values.map((e) => e.name)))();
  TextColumn get status => textEnum<TaskStatus>().check(
        status.isIn(TaskStatus.values.map((e) => e.name)),
      )();
  DateTimeColumn get deadline => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

@UseRowClass(Comment)
@TableIndex(name: 'idx_comments_task', columns: {#taskId, #createdAt})
class Comments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();

  /// После удаления автора комментарий остаётся без подписи.
  IntColumn get authorId => integer()
      .nullable()
      .references(Users, #id, onDelete: KeyAction.setNull)();
  TextColumn get body => text().withLength(min: 1, max: 2000)();
  DateTimeColumn get createdAt => dateTime()();
}

/// Хранится только путь: содержимое файла лежит на диске.
@UseRowClass(Attachment)
@TableIndex(name: 'idx_attachments_task', columns: {#taskId})
class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text()();
  TextColumn get filePath => text()();
  DateTimeColumn get addedAt => dateTime()();
}

@UseRowClass(TaskHistoryEntry)
@TableIndex(name: 'idx_history_task', columns: {#taskId, #id})
class TaskHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get event => textEnum<HistoryEvent>()();
  TextColumn get oldStatus => textEnum<TaskStatus>().nullable()();
  TextColumn get newStatus => textEnum<TaskStatus>().nullable()();
  IntColumn get oldAssigneeId => integer()
      .nullable()
      .references(Users, #id, onDelete: KeyAction.setNull)();
  IntColumn get newAssigneeId => integer()
      .nullable()
      .references(Users, #id, onDelete: KeyAction.setNull)();
  IntColumn get changedBy => integer()
      .nullable()
      .references(Users, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get changedAt => dateTime()();
}

/// Настройки приложения, например выбранный текущий пользователь.
@UseRowClass(AppSetting)
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
