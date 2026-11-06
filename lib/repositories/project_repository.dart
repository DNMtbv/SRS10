import 'package:drift/drift.dart';

import '../core/app_exception.dart';
import '../core/clock.dart';
import '../core/validators.dart';
import '../database/app_database.dart';
import '../models/entities.dart';
import '../models/enums.dart';
import '../models/views.dart';

class ProjectRepository {
  ProjectRepository(this._db, {Clock clock = systemClock}) : _now = clock;

  final AppDatabase _db;
  final Clock _now;

  Stream<List<Project>> watchProjects() => (_db.select(_db.projects)
        ..orderBy([
          (p) => OrderingTerm.desc(p.createdAt),
          (p) => OrderingTerm.desc(p.id),
        ]))
      .watch();

  Stream<Project?> watchProject(int id) =>
      (_db.select(_db.projects)..where((p) => p.id.equals(id)))
          .watchSingleOrNull();

  /// Проект и его владелец сохраняются вместе: проекта без Owner не бывает.
  Future<int> createProject({
    required String name,
    required int ownerId,
    String description = '',
    DateTime? dueDate,
  }) {
    final cleanName = Validators.title(name);
    final now = _now();
    _ensureDueDate(dueDate, now);
    return guardDb(
      () => _db.transaction(() async {
        final id = await _db.into(_db.projects).insert(
              ProjectsCompanion.insert(
                name: cleanName,
                description: Value(description.trim()),
                createdAt: now,
                dueDate: Value(dueDate),
                status: ProjectStatus.active,
              ),
            );
        await _db.into(_db.projectMembers).insert(
              ProjectMembersCompanion.insert(
                projectId: id,
                userId: ownerId,
                role: ProjectRole.owner,
                joinedAt: now,
              ),
            );
        return id;
      }),
    );
  }

  Future<void> updateProject({
    required int id,
    required String name,
    required String description,
    required ProjectStatus status,
    DateTime? dueDate,
  }) {
    final cleanName = Validators.title(name);
    return guardDb(() async {
      final project = await _requireProject(id);
      _ensureDueDate(dueDate, project.createdAt);
      await (_db.update(_db.projects)..where((p) => p.id.equals(id))).write(
        ProjectsCompanion(
          name: Value(cleanName),
          description: Value(description.trim()),
          status: Value(status),
          dueDate: Value(dueDate),
        ),
      );
    });
  }

  /// Участники, задачи, комментарии, вложения и история удаляются каскадно.
  Future<void> deleteProject(int id) => guardDb(() async {
        final deleted = await (_db.delete(_db.projects)
              ..where((p) => p.id.equals(id)))
            .go();
        if (deleted == 0) throw const NotFoundException('Проект не найден');
      });

  Stream<List<MemberView>> watchMembers(int projectId) =>
      _membersQuery(projectId).watch().map(_toMembers);

  /// Разовое чтение, например для выбора исполнителя.
  Future<List<MemberView>> getMembers(int projectId) =>
      _membersQuery(projectId).get().then(_toMembers);

  JoinedSelectStatement<HasResultSet, dynamic> _membersQuery(int projectId) {
    return _db.select(_db.projectMembers).join([
      innerJoin(
        _db.users,
        _db.users.id.equalsExp(_db.projectMembers.userId),
      ),
    ])
      ..where(_db.projectMembers.projectId.equals(projectId))
      ..orderBy([OrderingTerm.asc(_db.users.name)]);
  }

  List<MemberView> _toMembers(List<TypedResult> rows) => rows
      .map(
        (r) => MemberView(
          user: r.readTable(_db.users),
          role: r.readTable(_db.projectMembers).role,
        ),
      )
      .toList();

  Future<void> addMember({
    required int projectId,
    required int userId,
    ProjectRole role = ProjectRole.member,
  }) =>
      guardDb(
        () => _db.transaction(() async {
          await _requireProject(projectId);
          if (await _findMember(projectId, userId) != null) {
            throw const RuleViolationException(
              'Пользователь уже состоит в проекте',
            );
          }
          await _db.into(_db.projectMembers).insert(
                ProjectMembersCompanion.insert(
                  projectId: projectId,
                  userId: userId,
                  role: role,
                  joinedAt: _now(),
                ),
              );
        }),
      );

  /// Нельзя убрать единственного Owner и участника с незавершёнными задачами
  /// этого проекта: иначе у задачи окажется исполнитель не из проекта.
  Future<void> removeMember({required int projectId, required int userId}) =>
      guardDb(
        () => _db.transaction(() async {
          final member = await _findMember(projectId, userId);
          if (member == null) {
            throw const NotFoundException('Участник не найден');
          }
          await _ensureOwnerRemains(member);

          final open = _db.tasks.id.count();
          final query = _db.selectOnly(_db.tasks)
            ..addColumns([open])
            ..where(
              _db.tasks.projectId.equals(projectId) &
                  _db.tasks.assigneeId.equals(userId) &
                  _db.tasks.deletedAt.isNull() &
                  _db.tasks.status.isIn([
                    TaskStatus.todo.name,
                    TaskStatus.inProgress.name,
                  ]),
            );
          final count = (await query.getSingle()).read(open)!;
          if (count > 0) {
            throw RuleViolationException(
              'У участника незавершённых задач в проекте: $count',
            );
          }

          await (_db.delete(_db.projectMembers)
                ..where(
                  (m) =>
                      m.projectId.equals(projectId) & m.userId.equals(userId),
                ))
              .go();
        }),
      );

  Future<void> changeRole({
    required int projectId,
    required int userId,
    required ProjectRole role,
  }) =>
      guardDb(
        () => _db.transaction(() async {
          final member = await _findMember(projectId, userId);
          if (member == null) {
            throw const NotFoundException('Участник не найден');
          }
          if (role != ProjectRole.owner) await _ensureOwnerRemains(member);
          await (_db.update(_db.projectMembers)
                ..where(
                  (m) =>
                      m.projectId.equals(projectId) & m.userId.equals(userId),
                ))
              .write(ProjectMembersCompanion(role: Value(role)));
        }),
      );

  Future<void> _ensureOwnerRemains(ProjectMember member) async {
    if (member.role != ProjectRole.owner) return;
    final owners = await (_db.select(_db.projectMembers)
          ..where(
            (m) =>
                m.projectId.equals(member.projectId) &
                m.role.equals(ProjectRole.owner.name),
          ))
        .get();
    if (owners.length == 1) {
      throw const RuleViolationException(
        'В проекте должен остаться хотя бы один Owner',
      );
    }
  }

  Future<ProjectMember?> _findMember(int projectId, int userId) =>
      (_db.select(_db.projectMembers)
            ..where(
              (m) => m.projectId.equals(projectId) & m.userId.equals(userId),
            ))
          .getSingleOrNull();

  Future<Project> _requireProject(int id) async {
    final project = await (_db.select(_db.projects)
          ..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    if (project == null) throw const NotFoundException('Проект не найден');
    return project;
  }

  void _ensureDueDate(DateTime? dueDate, DateTime createdAt) {
    if (dueDate != null && startOfDay(dueDate).isBefore(startOfDay(createdAt))) {
      throw const ValidationException(
        'Дата завершения раньше даты создания проекта',
      );
    }
  }
}
