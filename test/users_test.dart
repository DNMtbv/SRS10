import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/app_exception.dart';
import 'package:taskflow/models/enums.dart';
import 'package:taskflow/models/views.dart';

import 'helpers/world.dart';

void main() {
  late World w;

  setUp(() async => w = await World.create());

  test('создание: имя и email сохраняются, дата регистрации заполняется',
      () async {
    final id = await w.users.createUser(
      name: '  Дана Серик  ',
      email: 'Dana@Mail.KZ',
    );

    final user = await w.users.watchUser(id).first;
    expect(user!.name, 'Дана Серик');
    expect(user.email, 'dana@mail.kz');
    expect(user.registeredAt, w.now);
  });

  test('email уникален без учёта регистра', () async {
    await expectLater(
      w.users.createUser(name: 'Копия', email: 'ANNA@mail.kz'),
      throwsA(isA<RuleViolationException>()),
    );
  });

  test('редактирование не даёт занять чужой email, свой оставить можно',
      () async {
    await expectLater(
      w.users.updateUser(id: w.boris, name: 'Борис', email: 'anna@mail.kz'),
      throwsA(isA<RuleViolationException>()),
    );

    await w.users.updateUser(id: w.boris, name: 'Борис', email: 'boris@mail.kz');
    expect((await w.users.watchUser(w.boris).first)!.name, 'Борис');
  });

  test('некорректные имя и email не сохраняются', () async {
    expect(
      () => w.users.createUser(name: 'А', email: 'a@mail.kz'),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => w.users.createUser(name: 'Анна', email: 'not-an-email'),
      throwsA(isA<ValidationException>()),
    );
  });

  test('пользователя без связей можно удалить', () async {
    await w.users.deleteUser(w.outsider);
    expect(await w.users.watchUser(w.outsider).first, isNull);
  });

  test('нельзя удалить пользователя с незавершёнными задачами', () async {
    await w.task();

    await expectLater(
      w.users.deleteUser(w.boris),
      throwsA(isA<RuleViolationException>()),
    );
    expect(await w.users.watchUser(w.boris).first, isNotNull);
  });

  test('после завершения задачи удаление разрешено, задача остаётся', () async {
    final id = await w.task();
    await w.tasks.changeStatus(id: id, status: TaskStatus.done, actorId: w.anna);

    await w.users.deleteUser(w.boris);

    final view = await w.tasks.watchTask(id).first;
    expect(view!.task.assigneeId, isNull);
    final history = await w.tasks.watchHistory(id).first;
    expect(history, hasLength(2));
  });

  test('список задач конкретного исполнителя', () async {
    await w.task(title: 'Для Бориса');
    await w.task(title: 'Для Анны', assignee: w.anna);

    final tasks = await w.tasks.getTasksPage(
      TaskFilter(assigneeId: w.boris),
      limit: 20,
    );

    expect(tasks.map((t) => t.task.title), ['Для Бориса']);
  });
}
