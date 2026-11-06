import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/app_exception.dart';
import 'package:taskflow/database/app_database.dart';
import 'package:taskflow/models/enums.dart';
import 'package:taskflow/models/views.dart';
import 'package:taskflow/state/feature_cubits.dart';
import 'package:taskflow/state/session_cubit.dart';
import 'package:taskflow/state/task_details_cubit.dart';
import 'package:taskflow/state/tasks_cubit.dart';

import 'helpers/world.dart';

void main() {
  late World w;

  setUp(() async => w = await World.create());

  Future<void> addTasks(int count) => w.db.batch((b) {
        for (var i = 1; i <= count; i++) {
          b.insert(
            w.db.tasks,
            TasksCompanion.insert(
              title: 'Задача $i',
              projectId: w.project,
              status: TaskStatus.todo,
              deadline: w.deadline,
              createdAt: w.now,
              updatedAt: w.now,
            ),
          );
        }
      });

  Future<T> until<T>(Stream<T> states, bool Function(T) test) =>
      states.firstWhere(test);

  group('TasksCubit', () {
    test('пагинация: сначала 20 задач, loadMore добавляет следующую страницу',
        () async {
      await addTasks(45);
      final cubit = TasksCubit(w.tasks);
      addTearDown(cubit.close);

      await until(cubit.stream, (s) => !s.isLoading);
      expect(cubit.state.items, hasLength(20));
      expect(cubit.state.hasMore, isTrue);

      cubit.loadMore();
      await until(cubit.stream, (s) => !s.isLoading);
      expect(cubit.state.items, hasLength(40));

      cubit.loadMore();
      await until(cubit.stream, (s) => !s.isLoading);
      expect(cubit.state.items, hasLength(45));
      expect(cubit.state.hasMore, isFalse);
    });

    test('смена фильтра сбрасывает список на первую страницу', () async {
      await addTasks(45);
      final cubit = TasksCubit(w.tasks);
      addTearDown(cubit.close);
      await until(cubit.stream, (s) => !s.isLoading);
      cubit.loadMore();
      await until(cubit.stream, (s) => !s.isLoading);

      cubit.setStatus(TaskStatus.todo);
      await until(cubit.stream, (s) => !s.isLoading);

      expect(cubit.state.limit, TasksCubit.pageSize);
      expect(cubit.state.items, hasLength(20));
    });

    test('новая задача появляется в списке без перезагрузки', () async {
      final cubit = TasksCubit(w.tasks);
      addTearDown(cubit.close);
      await until(cubit.stream, (s) => !s.isLoading);
      expect(cubit.state.items, isEmpty);

      await w.task(title: 'Новая');

      final state = await until(cubit.stream, (s) => s.items.isNotEmpty);
      expect(state.items.single.task.title, 'Новая');
    });

    test('поиск срабатывает только после паузы в наборе', () async {
      await w.task(title: 'Отчёт');
      await w.task(title: 'Сервер');
      final cubit = TasksCubit(
        w.tasks,
        searchDelay: const Duration(milliseconds: 10),
      );
      addTearDown(cubit.close);
      await until(cubit.stream, (s) => !s.isLoading);

      cubit
        ..setQuery('о')
        ..setQuery('от')
        ..setQuery('отчёт');
      expect(cubit.state.filter.query, '');

      final state = await until(
        cubit.stream,
        (s) => s.filter.query == 'отчёт' && !s.isLoading,
      );
      expect(state.items.single.task.title, 'Отчёт');
    });

    test('сброс фильтра возвращает все задачи', () async {
      await w.task();
      final filtered = TasksCubit(
        w.tasks,
        filter: TaskFilter(assigneeId: w.anna),
      );
      addTearDown(filtered.close);
      await until(filtered.stream, (s) => !s.isLoading);
      expect(filtered.state.items, isEmpty);

      filtered.setAssignee(null);
      final state = await until(filtered.stream, (s) => s.items.isNotEmpty);

      expect(state.filter.assigneeId, isNull);
    });
  });

  group('TaskDetailsCubit', () {
    test('состояние обновляется само: статус, история и Undo', () async {
      final id = await w.task();
      final cubit = TaskDetailsCubit(
        taskId: id,
        tasks: w.tasks,
        comments: w.comments,
        attachments: w.attachments,
      );
      addTearDown(cubit.close);
      await until(cubit.stream, (s) => s.task != null && s.history.isNotEmpty);
      expect(cubit.state.canUndo, isFalse);

      await cubit.changeStatus(TaskStatus.inProgress, w.boris);
      final changed = await until(
        cubit.stream,
        (s) => s.history.length == 2 && s.task!.task.status.name == 'inProgress',
      );
      expect(changed.canUndo, isTrue);

      await cubit.undoStatus(w.boris);
      final undone = await until(cubit.stream, (s) => s.history.length == 3);
      expect(undone.canUndo, isFalse);
    });

    test('удалённая задача становится null, экран это покажет', () async {
      final id = await w.task();
      final cubit = TaskDetailsCubit(
        taskId: id,
        tasks: w.tasks,
        comments: w.comments,
        attachments: w.attachments,
      );
      addTearDown(cubit.close);
      await until(cubit.stream, (s) => s.task != null);

      await w.tasks.moveToTrash(id);
      await w.tasks.deletePermanently(id);

      final state = await until(cubit.stream, (s) => s.task == null);
      expect(state.isLoading, isFalse);
    });
  });

  group('SessionCubit', () {
    test('без выбора действие требует пользователя', () async {
      final cubit = SessionCubit(w.users);
      addTearDown(cubit.close);

      expect(cubit.requireUserId, throwsA(isA<RuleViolationException>()));
    });

    test('выбор сохраняется в базе и переживает новый запуск', () async {
      final first = SessionCubit(w.users);
      await first.select(w.boris);
      await until(first.stream, (u) => u != null);
      await first.close();

      final second = SessionCubit(w.users);
      addTearDown(second.close);
      final user = await until(second.stream, (u) => u != null);

      expect(user!.id, w.boris);
    });

    test('смена пользователя применяется сразу, и не один раз', () async {
      final cubit = SessionCubit(w.users);
      addTearDown(cubit.close);

      for (final id in [w.anna, w.boris, w.anna]) {
        await cubit.select(id);
        final user = await until(cubit.stream, (u) => u?.id == id)
            .timeout(const Duration(seconds: 2));
        expect(user!.id, id);
      }
    });

    test('новый выбор работает и после очистки базы', () async {
      final cubit = SessionCubit(w.users);
      addTearDown(cubit.close);
      await cubit.select(w.anna);
      await until(cubit.stream, (u) => u != null);

      await w.maintenance.clearAll();
      await until(cubit.stream, (u) => u == null);

      final id = await w.users.createUser(name: 'Новая', email: 'new@mail.kz');
      await cubit.select(id);
      final user = await until(cubit.stream, (u) => u != null)
          .timeout(const Duration(seconds: 2));
      expect(user!.id, id);
    });

    test('удаление текущего пользователя сбрасывает выбор', () async {
      final cubit = SessionCubit(w.users);
      addTearDown(cubit.close);
      await cubit.select(w.outsider);
      await until(cubit.stream, (u) => u != null);

      await w.users.deleteUser(w.outsider);

      await until(cubit.stream, (u) => u == null);
      expect(cubit.state, isNull);
    });
  });

  test('DashboardCubit собирает данные всех запросов и следит за ними',
      () async {
    final cubit = DashboardCubit(w.stats);
    addTearDown(cubit.close);
    await until(cubit.stream, (s) => s.progress.isNotEmpty);

    await w.task();

    final state = await until(
      cubit.stream,
      (s) =>
          s.summary.tasks == 1 &&
          s.byPriority[TaskPriority.medium] == 1 &&
          s.byAssignee.first.tasks == 1,
    );
    expect(state.byAssignee.first.name, 'Борис Ли');
  });

  test('ToolsCubit сравнивает скорость на временной базе, рабочую не меняет',
      () async {
    final cubit = ToolsCubit(w.maintenance);
    addTearDown(cubit.close);
    final before = await w.db.select(w.db.tasks).get();

    await cubit.runBenchmark();

    expect(cubit.state.results, hasLength(9));
    expect(cubit.state.busy, isNull);
    expect(await w.db.select(w.db.tasks).get(), hasLength(before.length));
    final indexes = await w.db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name LIKE 'idx_tasks_%'",
        )
        .get();
    expect(indexes, hasLength(6));
  });
}
