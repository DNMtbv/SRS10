import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/app_exception.dart';
import 'package:taskflow/models/enums.dart';
import 'package:taskflow/models/views.dart';

import 'helpers/world.dart';

void main() {
  late World w;

  setUp(() async => w = await World.create());

  test('создание: проект активный, создатель становится Owner', () async {
    final id = await w.projects.createProject(
      name: '  Новый проект  ',
      description: 'Описание',
      dueDate: DateTime(2026, 12, 31),
      ownerId: w.boris,
    );

    final project = await w.projects.watchProject(id).first;
    expect(project!.name, 'Новый проект');
    expect(project.status, ProjectStatus.active);
    expect(project.createdAt, w.now);
    expect(project.dueDate, DateTime(2026, 12, 31));

    final members = await w.projects.watchMembers(id).first;
    expect(members.single.user.id, w.boris);
    expect(members.single.role, ProjectRole.owner);
  });

  test('дата завершения не может быть раньше даты создания', () async {
    expect(
      () => w.projects.createProject(
        name: 'Проект',
        ownerId: w.anna,
        dueDate: DateTime(2026, 6, 1),
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('редактирование меняет поля и статус', () async {
    await w.projects.updateProject(
      id: w.project,
      name: 'Новое имя',
      description: 'Текст',
      status: ProjectStatus.archived,
    );

    final project = await w.projects.watchProject(w.project).first;
    expect(project!.name, 'Новое имя');
    expect(project.status, ProjectStatus.archived);
  });

  test('Many-to-Many: один пользователь в двух проектах с разными ролями',
      () async {
    final second = await w.projects.createProject(
      name: 'Второй',
      ownerId: w.boris,
    );

    final first = await w.projects.watchMembers(w.project).first;
    final other = await w.projects.watchMembers(second).first;

    expect(first.firstWhere((m) => m.user.id == w.boris).role,
        ProjectRole.member);
    expect(other.firstWhere((m) => m.user.id == w.boris).role,
        ProjectRole.owner);
  });

  test('добавление участника с ролью и смена роли', () async {
    await w.projects.addMember(
      projectId: w.project,
      userId: w.outsider,
      role: ProjectRole.admin,
    );
    await w.projects.changeRole(
      projectId: w.project,
      userId: w.outsider,
      role: ProjectRole.member,
    );

    final members = await w.projects.watchMembers(w.project).first;
    expect(members, hasLength(3));
    expect(members.firstWhere((m) => m.user.id == w.outsider).role,
        ProjectRole.member);
  });

  test('одного пользователя нельзя добавить в проект дважды', () async {
    await expectLater(
      w.projects.addMember(projectId: w.project, userId: w.boris),
      throwsA(isA<RuleViolationException>()),
    );
    expect(await w.projects.watchMembers(w.project).first, hasLength(2));
  });

  test('UNIQUE в базе: повторная пара отклоняется и без проверки в коде',
      () async {
    await expectLater(
      w.db.customStatement(
        'INSERT INTO project_members (project_id, user_id, role, joined_at) '
        "VALUES (${w.project}, ${w.boris}, 'member', 0)",
      ),
      throwsA(anything),
    );
  });

  test('нельзя убрать участника с незавершёнными задачами проекта', () async {
    final id = await w.task();

    await expectLater(
      w.projects.removeMember(projectId: w.project, userId: w.boris),
      throwsA(isA<RuleViolationException>()),
    );

    await w.tasks.changeStatus(id: id, status: TaskStatus.done, actorId: w.anna);
    await w.projects.removeMember(projectId: w.project, userId: w.boris);
    expect(await w.projects.watchMembers(w.project).first, hasLength(1));
  });

  test('в проекте всегда остаётся хотя бы один Owner', () async {
    await expectLater(
      w.projects.removeMember(projectId: w.project, userId: w.anna),
      throwsA(isA<RuleViolationException>()),
    );
    await expectLater(
      w.projects.changeRole(
        projectId: w.project,
        userId: w.anna,
        role: ProjectRole.member,
      ),
      throwsA(isA<RuleViolationException>()),
    );
  });

  test('удаление проекта каскадно удаляет его задачи и участников', () async {
    final id = await w.task();
    await w.comments.addComment(taskId: id, authorId: w.anna, body: 'Текст');

    await w.projects.deleteProject(w.project);

    expect(await w.tasks.watchTask(id).first, isNull);
    expect(await w.projects.watchMembers(w.project).first, isEmpty);
    expect(await w.comments.watchComments(id).first, isEmpty);
    expect(await w.tasks.watchHistory(id).first, isEmpty);
    final left = await w.tasks.getTasksPage(const TaskFilter(), limit: 20);
    expect(left, isEmpty);
  });
}
