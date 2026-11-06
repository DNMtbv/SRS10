import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/app_exception.dart';
import 'package:taskflow/database/app_database.dart';
import 'package:taskflow/models/enums.dart';
import 'package:taskflow/models/views.dart';
import 'package:taskflow/repositories/task_repository.dart';

import 'helpers/world.dart';

void main() {
  late World w;

  setUp(() async => w = await World.create());

  Future<int> taskRows() async =>
      (await w.db.select(w.db.tasks).get()).length;
  Future<int> historyRows() async =>
      (await w.db.select(w.db.taskHistory).get()).length;

  group('создание', () {
    test('все поля сохраняются, новая задача получает статус todo', () async {
      final id = await w.tasks.createTask(
        title: '  Написать отчёт  ',
        description: 'Подробно',
        projectId: w.project,
        assigneeId: w.boris,
        priority: TaskPriority.critical,
        deadline: DateTime(2026, 6, 20, 18, 30),
        actorId: w.anna,
      );

      final view = (await w.tasks.watchTask(id).first)!;
      expect(view.task.title, 'Написать отчёт');
      expect(view.task.status, TaskStatus.todo);
      expect(view.task.priority, TaskPriority.critical);
      expect(view.task.deadline, DateTime(2026, 6, 20));
      expect(view.task.createdAt, w.now);
      expect(view.task.updatedAt, w.now);
      expect(view.projectName, 'Сайт');
      expect(view.assigneeName, 'Борис Ли');
    });

    test('пустое название не сохраняется', () async {
      expect(
        () => w.tasks.createTask(
          title: '   ',
          projectId: w.project,
          assigneeId: w.boris,
          deadline: w.deadline,
          actorId: w.anna,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('нельзя создать задачу в несуществующем проекте', () async {
      await expectLater(
        w.tasks.createTask(
          title: 'Задача',
          projectId: 999,
          assigneeId: w.boris,
          deadline: w.deadline,
          actorId: w.anna,
        ),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('внешний ключ не пускает задачу без проекта мимо репозитория',
        () async {
      await expectLater(
        w.db.into(w.db.tasks).insert(
              TasksCompanion.insert(
                title: 'Без проекта',
                projectId: 999,
                status: TaskStatus.todo,
                deadline: w.deadline,
                createdAt: w.now,
                updatedAt: w.now,
              ),
            ),
        throwsA(anything),
      );
      expect(await taskRows(), 0);
    });

    test('исполнитель не из проекта отклоняется', () async {
      await expectLater(
        w.task(assignee: w.outsider),
        throwsA(isA<RuleViolationException>()),
      );
      expect(await taskRows(), 0);
    });
  });

  group('транзакции', () {
    test('создание пишет первую запись истории', () async {
      final id = await w.task();

      final history = await w.tasks.watchHistory(id).first;
      expect(history.single.entry.event, HistoryEvent.created);
      expect(history.single.entry.newStatus, TaskStatus.todo);
      expect(history.single.actorName, 'Анна Ким');
    });

    test('ошибка записи истории откатывает создание задачи', () async {
      // Автора 9999 нет: задача уже вставлена, падает именно вставка истории.
      await expectLater(
        w.tasks.createTask(
          title: 'Не должна сохраниться',
          projectId: w.project,
          assigneeId: w.boris,
          deadline: w.deadline,
          actorId: 9999,
        ),
        throwsA(isA<DataIntegrityException>()),
      );

      expect(await taskRows(), 0);
      expect(await historyRows(), 0);
    });

    test('переназначение: исполнитель меняется вместе с записью истории',
        () async {
      final id = await w.task();

      await w.tasks.reassign(id: id, assigneeId: w.anna, actorId: w.anna);

      expect((await w.tasks.watchTask(id).first)!.task.assigneeId, w.anna);
      final last = (await w.tasks.watchHistory(id).first).first;
      expect(last.entry.event, HistoryEvent.reassigned);
      expect(last.oldAssigneeName, 'Борис Ли');
      expect(last.newAssigneeName, 'Анна Ким');
    });

    test('переназначение на пользователя не из проекта ничего не меняет',
        () async {
      final id = await w.task();

      await expectLater(
        w.tasks.reassign(id: id, assigneeId: w.outsider, actorId: w.anna),
        throwsA(isA<RuleViolationException>()),
      );

      expect((await w.tasks.watchTask(id).first)!.task.assigneeId, w.boris);
      expect(await historyRows(), 1);
    });

    test('ошибка истории откатывает смену исполнителя', () async {
      final id = await w.task();

      await expectLater(
        w.tasks.reassign(id: id, assigneeId: w.anna, actorId: 9999),
        throwsA(isA<DataIntegrityException>()),
      );

      expect((await w.tasks.watchTask(id).first)!.task.assigneeId, w.boris);
    });

    test('ошибка истории откатывает смену статуса', () async {
      final id = await w.task();

      await expectLater(
        w.tasks.changeStatus(
          id: id,
          status: TaskStatus.done,
          actorId: 9999,
        ),
        throwsA(isA<DataIntegrityException>()),
      );

      expect((await w.tasks.watchTask(id).first)!.task.status, TaskStatus.todo);
    });
  });

  group('статус и история', () {
    test('каждая смена статуса записывается со всеми полями', () async {
      final id = await w.task();
      w.now = DateTime(2026, 6, 16, 9);

      await w.tasks.changeStatus(
        id: id,
        status: TaskStatus.inProgress,
        actorId: w.boris,
      );

      final view = (await w.tasks.watchTask(id).first)!;
      expect(view.task.status, TaskStatus.inProgress);
      expect(view.task.updatedAt, w.now);

      final entry = (await w.tasks.watchHistory(id).first).first;
      expect(entry.entry.taskId, id);
      expect(entry.entry.event, HistoryEvent.statusChanged);
      expect(entry.entry.oldStatus, TaskStatus.todo);
      expect(entry.entry.newStatus, TaskStatus.inProgress);
      expect(entry.actorName, 'Борис Ли');
      expect(entry.entry.changedAt, w.now);
    });

    test('тот же статус не создаёт запись истории', () async {
      final id = await w.task();

      await w.tasks.changeStatus(id: id, status: TaskStatus.todo, actorId: w.anna);

      expect(await historyRows(), 1);
    });

    test('смена приоритета сохраняется и обновляет дату изменения', () async {
      final id = await w.task();
      w.now = DateTime(2026, 6, 16);

      await w.tasks.changePriority(id, TaskPriority.high);

      final task = (await w.tasks.watchTask(id).first)!.task;
      expect(task.priority, TaskPriority.high);
      expect(task.updatedAt, w.now);
    });
  });

  group('Undo', () {
    test('возвращает предыдущий статус и пишет отмену в историю', () async {
      final id = await w.task();
      await w.tasks.changeStatus(
        id: id,
        status: TaskStatus.inProgress,
        actorId: w.boris,
      );

      await w.tasks.undoLastStatusChange(id: id, actorId: w.boris);

      expect((await w.tasks.watchTask(id).first)!.task.status, TaskStatus.todo);
      final last = (await w.tasks.watchHistory(id).first).first;
      expect(last.entry.event, HistoryEvent.statusUndone);
      expect(last.entry.oldStatus, TaskStatus.inProgress);
      expect(last.entry.newStatus, TaskStatus.todo);
    });

    test('отменённое изменение нельзя отменить повторно', () async {
      final id = await w.task();
      await w.tasks.changeStatus(id: id, status: TaskStatus.done, actorId: w.anna);
      await w.tasks.undoLastStatusChange(id: id, actorId: w.anna);

      await expectLater(
        w.tasks.undoLastStatusChange(id: id, actorId: w.anna),
        throwsA(isA<RuleViolationException>()),
      );
    });

    test('у новой задачи отменять нечего', () async {
      final id = await w.task();

      await expectLater(
        w.tasks.undoLastStatusChange(id: id, actorId: w.anna),
        throwsA(isA<RuleViolationException>()),
      );
    });

    test('canUndo отражает состояние истории', () async {
      final id = await w.task();
      Future<bool> canUndo() async =>
          w.tasks.watchHistory(id).first.then(TaskRepository.canUndo);

      expect(await canUndo(), isFalse);
      await w.tasks.changeStatus(id: id, status: TaskStatus.done, actorId: w.anna);
      expect(await canUndo(), isTrue);
      await w.tasks.undoLastStatusChange(id: id, actorId: w.anna);
      expect(await canUndo(), isFalse);
    });
  });

  group('лимит три задачи на дату', () {
    test('четвёртая незавершённая задача на дату запрещена', () async {
      for (var i = 0; i < 3; i++) {
        await w.task();
      }

      await expectLater(w.task(), throwsA(isA<RuleViolationException>()));
      expect(await taskRows(), 3);
    });

    test('время в дедлайне не обходит лимит', () async {
      for (var i = 0; i < 3; i++) {
        await w.task();
      }

      await expectLater(
        w.task(deadline: DateTime(2026, 6, 20, 23, 59)),
        throwsA(isA<RuleViolationException>()),
      );
    });

    test('на другую дату и другому исполнителю назначить можно', () async {
      for (var i = 0; i < 3; i++) {
        await w.task();
      }

      await w.task(deadline: DateTime(2026, 6, 21));
      await w.task(assignee: w.anna);

      expect(await taskRows(), 5);
    });

    test('завершённые, отменённые и удалённые задачи не считаются', () async {
      final done = await w.task();
      final cancelled = await w.task();
      final trashed = await w.task();
      await w.tasks.changeStatus(
        id: done,
        status: TaskStatus.done,
        actorId: w.anna,
      );
      await w.tasks.changeStatus(
        id: cancelled,
        status: TaskStatus.cancelled,
        actorId: w.anna,
      );
      await w.tasks.moveToTrash(trashed);

      expect(await w.tasks.openTasksOnDay(w.boris, w.deadline), 0);
      await w.task();
      expect(await w.tasks.openTasksOnDay(w.boris, w.deadline), 1);
    });

    test('переназначение тоже проверяет лимит', () async {
      for (var i = 0; i < 3; i++) {
        await w.task();
      }
      final id = await w.task(assignee: w.anna);

      await expectLater(
        w.tasks.reassign(id: id, assigneeId: w.boris, actorId: w.anna),
        throwsA(isA<RuleViolationException>()),
      );
      expect((await w.tasks.watchTask(id).first)!.task.assigneeId, w.anna);
    });

    test('перенос дедлайна на занятую дату запрещён', () async {
      for (var i = 0; i < 3; i++) {
        await w.task();
      }
      final id = await w.task(deadline: DateTime(2026, 6, 25));

      await expectLater(
        w.tasks.updateTask(
          id: id,
          title: 'Задача',
          description: '',
          priority: TaskPriority.medium,
          deadline: w.deadline,
        ),
        throwsA(isA<RuleViolationException>()),
      );
    });

    test('редактирование без смены дедлайна не упирается в лимит', () async {
      final id = await w.task();
      await w.task();
      await w.task();

      await w.tasks.updateTask(
        id: id,
        title: 'Новое название',
        description: '',
        priority: TaskPriority.low,
        deadline: w.deadline,
      );

      final task = (await w.tasks.watchTask(id).first)!.task;
      expect(task.title, 'Новое название');
      expect(task.priority, TaskPriority.low);
    });
  });

  group('корзина', () {
    test('Soft Delete: строка остаётся в базе, списки её не показывают',
        () async {
      final id = await w.task();

      await w.tasks.moveToTrash(id);

      final row = await (w.db.select(w.db.tasks)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.deletedAt, w.now);
      expect(
        await w.tasks.getTasksPage(const TaskFilter(), limit: 20),
        isEmpty,
      );
      final trash = await w.tasks.watchTrash().first;
      expect(trash.single.task.id, id);
    });

    test('восстановление возвращает задачу в списки', () async {
      final id = await w.task(title: 'Вернусь');
      await w.tasks.moveToTrash(id);

      await w.tasks.restore(id);

      final tasks = await w.tasks.getTasksPage(const TaskFilter(), limit: 20);
      expect(tasks.single.task.title, 'Вернусь');
      expect(await w.tasks.watchTrash().first, isEmpty);
    });

    test('полное удаление убирает строку и связанные записи', () async {
      final id = await w.task();
      await w.comments.addComment(taskId: id, authorId: w.anna, body: 'Текст');
      await w.tasks.moveToTrash(id);

      await w.tasks.deletePermanently(id);

      expect(await taskRows(), 0);
      expect(await historyRows(), 0);
      expect(await w.comments.watchComments(id).first, isEmpty);
    });

    test('полностью удалить можно только задачу из корзины', () async {
      final id = await w.task();

      await expectLater(
        w.tasks.deletePermanently(id),
        throwsA(isA<NotFoundException>()),
      );
      expect(await taskRows(), 1);
    });

    test('задачу в корзине нельзя менять и комментировать', () async {
      final id = await w.task();
      await w.tasks.moveToTrash(id);

      await expectLater(
        w.tasks.changeStatus(id: id, status: TaskStatus.done, actorId: w.anna),
        throwsA(isA<NotFoundException>()),
      );
      await expectLater(
        w.comments.addComment(taskId: id, authorId: w.anna, body: 'Текст'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('фильтры, сортировка и поиск', () {
    late int design;
    late int report;
    late int server;

    setUp(() async {
      design = await w.tasks.createTask(
        title: 'Дизайн главной',
        description: 'Макеты для САЙТА',
        projectId: w.project,
        assigneeId: w.boris,
        priority: TaskPriority.high,
        deadline: DateTime(2026, 6, 30),
        actorId: w.anna,
      );
      w.now = DateTime(2026, 6, 16);
      report = await w.tasks.createTask(
        title: 'Отчёт',
        projectId: w.project,
        assigneeId: w.anna,
        priority: TaskPriority.low,
        deadline: DateTime(2026, 6, 18),
        actorId: w.anna,
      );
      w.now = DateTime(2026, 6, 17);
      server = await w.tasks.createTask(
        title: 'Настроить server',
        projectId: w.project,
        assigneeId: w.boris,
        priority: TaskPriority.high,
        deadline: DateTime(2026, 6, 25),
        actorId: w.anna,
      );
      await w.tasks.changeStatus(
        id: server,
        status: TaskStatus.done,
        actorId: w.anna,
      );
    });

    Future<List<int>> ids(TaskFilter filter) async {
      final page = await w.tasks.getTasksPage(filter, limit: 20);
      return page.map((t) => t.task.id).toList();
    }

    test('по статусу', () async {
      expect(await ids(const TaskFilter(status: TaskStatus.done)), [server]);
    });

    test('по приоритету', () async {
      expect(
        await ids(const TaskFilter(priority: TaskPriority.high)),
        [server, design],
      );
    });

    test('по исполнителю', () async {
      expect(await ids(TaskFilter(assigneeId: w.anna)), [report]);
    });

    test('фильтры сочетаются', () async {
      expect(
        await ids(
          TaskFilter(
            assigneeId: w.boris,
            priority: TaskPriority.high,
            status: TaskStatus.todo,
          ),
        ),
        [design],
      );
    });

    test('задачи конкретного проекта', () async {
      final other = await w.projects.createProject(
        name: 'Другой',
        ownerId: w.anna,
      );
      expect(await ids(TaskFilter(projectId: other)), isEmpty);
      expect(await ids(TaskFilter(projectId: w.project)), hasLength(3));
    });

    test('сортировка по дате создания', () async {
      expect(await ids(const TaskFilter()), [server, report, design]);
      expect(
        await ids(const TaskFilter(sort: TaskSort.createdAsc)),
        [design, report, server],
      );
    });

    test('сортировка по дедлайну', () async {
      expect(
        await ids(const TaskFilter(sort: TaskSort.deadlineAsc)),
        [report, server, design],
      );
      expect(
        await ids(const TaskFilter(sort: TaskSort.deadlineDesc)),
        [design, server, report],
      );
    });

    test('поиск по названию не зависит от регистра кириллицы', () async {
      expect(await ids(const TaskFilter(query: 'ДИЗАЙН')), [design]);
      expect(await ids(const TaskFilter(query: 'отчёт')), [report]);
    });

    test('поиск по описанию', () async {
      expect(await ids(const TaskFilter(query: 'макеты для сайта')), [design]);
    });

    test('символы % и _ в поиске обычные, а не шаблон', () async {
      expect(await ids(const TaskFilter(query: '%')), isEmpty);
      expect(await ids(const TaskFilter(query: '_')), isEmpty);
    });

    test('поиск видит обновлённое название', () async {
      await w.tasks.updateTask(
        id: report,
        title: 'Презентация',
        description: '',
        priority: TaskPriority.low,
        deadline: DateTime(2026, 6, 18),
      );

      expect(await ids(const TaskFilter(query: 'отчёт')), isEmpty);
      expect(await ids(const TaskFilter(query: 'презентация')), [report]);
    });
  });

  group('пагинация', () {
    test('страницы не пересекаются и покрывают все строки', () async {
      await w.db.batch((b) {
        for (var i = 1; i <= 25; i++) {
          b.insert(
            w.db.tasks,
            TasksCompanion.insert(
              title: 'Задача $i',
              projectId: w.project,
              assigneeId: Value(w.boris),
              status: TaskStatus.todo,
              deadline: w.deadline,
              createdAt: w.now,
              updatedAt: w.now,
            ),
          );
        }
      });

      final first = await w.tasks.getTasksPage(const TaskFilter(), limit: 10);
      final second = await w.tasks.getTasksPage(
        const TaskFilter(),
        limit: 10,
        offset: 10,
      );
      final third = await w.tasks.getTasksPage(
        const TaskFilter(),
        limit: 10,
        offset: 20,
      );

      expect(first, hasLength(10));
      expect(second, hasLength(10));
      expect(third, hasLength(5));
      final all = {...first, ...second, ...third}.map((t) => t.task.id).toSet();
      expect(all, hasLength(25));
    });
  });

  group('реактивность', () {
    test('watch() сам присылает новый список после записи', () async {
      final stream = w.tasks.watchTasks(const TaskFilter(), limit: 20);
      final expectation = expectLater(
        stream.map((list) => list.map((t) => t.task.title).toList()),
        emitsInOrder([
          <String>[],
          ['Новая'],
          <String>[],
        ]),
      );

      final id = await w.task(title: 'Новая');
      await pumpEventQueue();
      await w.tasks.moveToTrash(id);

      await expectation;
    });

    test('смена исполнителя обновляет отслеживаемую задачу', () async {
      final id = await w.task();
      final expectation = expectLater(
        w.tasks.watchTask(id).map((v) => v?.assigneeName),
        emitsInOrder(['Борис Ли', 'Анна Ким']),
      );

      await pumpEventQueue();
      await w.tasks.reassign(id: id, assigneeId: w.anna, actorId: w.anna);

      await expectation;
    });
  });
}
