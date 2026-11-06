import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/models/enums.dart';
import 'package:taskflow/models/views.dart';
import 'package:taskflow/repositories/maintenance_repository.dart';

import 'helpers/world.dart';

void main() {
  late World w;

  setUp(() async {
    w = await World.create();
    await w.maintenance.clearAll();
    await w.maintenance.seedLarge();
  });

  test('тестовая база: 1000 пользователей, 100 проектов, 10 000 задач', () async {
    expect(await w.db.select(w.db.users).get(), hasLength(1000));
    expect(await w.db.select(w.db.projects).get(), hasLength(100));
    expect(await w.db.select(w.db.tasks).get(), hasLength(10000));
  });

  test('поиск, фильтр и сортировка работают на большом объёме', () async {
    final found = await w.tasks.getTasksPage(
      const TaskFilter(query: 'задача 9999'),
      limit: 20,
    );
    expect(found.single.task.title, 'Задача 9999');

    final filtered = await w.tasks.getTasksPage(
      const TaskFilter(
        status: TaskStatus.done,
        priority: TaskPriority.critical,
        sort: TaskSort.deadlineAsc,
      ),
      limit: 20,
    );
    expect(filtered, hasLength(20));
    expect(
      filtered.every(
        (t) =>
            t.task.status == TaskStatus.done &&
            t.task.priority == TaskPriority.critical,
      ),
      isTrue,
    );
    final deadlines = filtered.map((t) => t.task.deadline).toList();
    expect(deadlines, orderedEquals([...deadlines]..sort()));
  });

  test('пагинация проходит все 10 000 задач без повторов', () async {
    final ids = <int>{};
    for (var offset = 0; offset < 10000; offset += 1000) {
      final page = await w.tasks.getTasksPage(
        const TaskFilter(),
        limit: 1000,
        offset: offset,
      );
      expect(page, hasLength(1000));
      ids.addAll(page.map((t) => t.task.id));
    }
    expect(ids, hasLength(10000));
  });

  test('индексы используются, а без них запросы сканируют таблицу', () async {
    final rows = await MaintenanceRepository.compareIndexes(
      w.db,
      clock: w.clock,
    );

    // ignore: avoid_print
    for (final r in rows) {
      // ignore: avoid_print
      print(
        '${r.name}: ${r.withIndexMs.toStringAsFixed(3)} мс → '
        '${r.withoutIndexMs.toStringAsFixed(3)} мс без индекса\n'
        '   с индексом: ${r.planWithIndex}\n'
        '   без индекса: ${r.planWithoutIndex}',
      );
    }

    final byName = {for (final r in rows) r.name: r};
    final status = byName['Фильтр по статусу']!;
    expect(status.planWithIndex, contains('idx_tasks_status_created'));
    expect(status.planWithoutIndex, contains('SCAN'));
    expect(status.planWithoutIndex, isNot(contains('idx_tasks')));

    final limit = byName['Лимит 3 задачи на дату']!;
    expect(limit.planWithIndex, contains('idx_tasks_assignee_deadline'));
    expect(limit.planWithoutIndex, contains('SCAN'));

    final deadline = byName['Сортировка по дедлайну']!;
    expect(deadline.planWithIndex, contains('idx_tasks_active_deadline'));
    // Полная сортировка не нужна: дедлайны уже идут по порядку из индекса,
    // досортировать остаётся только задачи с одинаковой датой.
    expect(deadline.planWithIndex, isNot(contains('TEMP B-TREE FOR ORDER BY')));
    expect(deadline.planWithoutIndex, contains('TEMP B-TREE FOR ORDER BY'));

    final overdue = byName['Просроченные задачи']!;
    expect(overdue.planWithIndex, contains('COVERING INDEX'));

    // Подстроку в середине текста обычный индекс ускорить не может.
    final search = byName['Поиск по тексту']!;
    expect(search.planWithIndex, isNot(contains('search_text')));
  });
}
