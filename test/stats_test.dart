import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/models/enums.dart';
import 'package:taskflow/models/views.dart';

import 'helpers/world.dart';

void main() {
  late World w;

  setUp(() async => w = await World.create());

  Future<void> setStatus(int id, TaskStatus status) =>
      w.tasks.changeStatus(id: id, status: status, actorId: w.anna);

  test('пустая база: все счётчики равны нулю', () async {
    await w.projects.deleteProject(w.project);

    expect(await w.stats.watchSummary().first, DashboardSummary.empty);
    final priorities = await w.stats.watchByPriority().first;
    expect(priorities.values, everyElement(0));
    expect(priorities.keys, TaskPriority.values);
  });

  test('сводка считает завершённые, незавершённые и просроченные', () async {
    await w.task(deadline: DateTime(2026, 6, 20));
    final late1 = await w.task(deadline: DateTime(2026, 6, 10));
    await w.task(deadline: DateTime(2026, 6, 11), assignee: w.anna);
    final doneLate = await w.task(deadline: DateTime(2026, 6, 9));
    final cancelled = await w.task(deadline: DateTime(2026, 6, 8));
    final trashed = await w.task(deadline: DateTime(2026, 6, 7));
    await setStatus(doneLate, TaskStatus.done);
    await setStatus(cancelled, TaskStatus.cancelled);
    await setStatus(late1, TaskStatus.inProgress);
    await w.tasks.moveToTrash(trashed);

    expect(
      await w.stats.watchSummary().first,
      const DashboardSummary(
        projects: 1,
        tasks: 5,
        done: 1,
        open: 3,
        cancelled: 1,
        overdue: 2,
      ),
    );
  });

  test('дедлайн сегодня ещё не считается просроченным', () async {
    await w.task(deadline: DateTime(2026, 6, 15));

    expect((await w.stats.watchSummary().first).overdue, 0);

    w.now = DateTime(2026, 6, 16, 0, 1);
    expect((await w.stats.watchSummary().first).overdue, 1);
  });

  test('количество задач по приоритетам', () async {
    await w.tasks.createTask(
      title: 'A',
      projectId: w.project,
      assigneeId: w.boris,
      priority: TaskPriority.critical,
      deadline: DateTime(2026, 6, 20),
      actorId: w.anna,
    );
    await w.tasks.createTask(
      title: 'B',
      projectId: w.project,
      assigneeId: w.boris,
      priority: TaskPriority.critical,
      deadline: DateTime(2026, 6, 21),
      actorId: w.anna,
    );
    await w.task(deadline: DateTime(2026, 6, 22));

    expect(await w.stats.watchByPriority().first, {
      TaskPriority.low: 0,
      TaskPriority.medium: 1,
      TaskPriority.high: 0,
      TaskPriority.critical: 2,
    });
  });

  test('количество задач у исполнителей, включая тех, у кого их нет', () async {
    await w.task();
    await w.task();
    await w.task(assignee: w.anna);

    expect(await w.stats.watchByAssignee().first, const [
      AssigneeLoad(name: 'Борис Ли', tasks: 2),
      AssigneeLoad(name: 'Анна Ким', tasks: 1),
      AssigneeLoad(name: 'Посторонний', tasks: 0),
    ]);
  });

  test('процент выполнения проекта без отменённых и удалённых задач', () async {
    final done = await w.task();
    final other = await w.task(assignee: w.anna);
    await w.task(assignee: w.anna);
    final cancelled = await w.task(assignee: w.anna);
    final trashed = await w.task(deadline: DateTime(2026, 6, 22));
    await setStatus(done, TaskStatus.done);
    await setStatus(other, TaskStatus.done);
    await setStatus(cancelled, TaskStatus.cancelled);
    await w.tasks.moveToTrash(trashed);

    final progress = (await w.stats.watchProjectProgress().first).single;

    expect(progress.done, 2);
    expect(progress.total, 3);
    expect(progress.percent, 67);
  });

  test('проект без задач имеет 0 %, деления на ноль нет', () async {
    final progress = (await w.stats.watchProjectProgress().first).single;

    expect(progress.total, 0);
    expect(progress.percent, 0);
  });

  test('статистика обновляется сама после изменения данных', () async {
    final expectation = expectLater(
      w.stats.watchSummary().map((s) => s.tasks),
      emitsInOrder([0, 1]),
    );

    await pumpEventQueue();
    await w.task();

    await expectation;
  });
}
