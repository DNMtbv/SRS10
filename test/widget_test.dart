import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/app.dart';
import 'package:taskflow/database/app_database.dart';
import 'package:taskflow/dependencies.dart';
import 'package:taskflow/models/enums.dart';

import 'helpers/world.dart';

void main() {
  late AppDatabase db;
  late Dependencies d;
  late int anna;
  late int boris;
  late int project;

  Future<void> prepare(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    db = memoryDatabase();
    d = Dependencies(
      database: db,
      attachmentsDirectory: () async => Directory.systemTemp,
      temporaryDirectory: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 6, 15, 12),
    );
    anna = await d.users.createUser(name: 'Анна Ким', email: 'anna@mail.kz');
    boris = await d.users.createUser(name: 'Борис Ли', email: 'boris@mail.kz');
    project = await d.projects.createProject(name: 'Сайт', ownerId: anna);
    await d.projects.addMember(projectId: project, userId: boris);
    await d.users.setCurrentUser(anna);

    await tester.pumpWidget(TaskFlowApp(dependencies: d));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  }

  Future<int> addTask(String title, {int? assignee}) => d.tasks.createTask(
        title: title,
        projectId: project,
        assigneeId: assignee ?? boris,
        deadline: DateTime(2026, 6, 20),
        actorId: anna,
      );

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(NavigationDestination, label));
    await tester.pumpAndSettle();
  }

  testWidgets('главный экран показывает проекты и вкладки', (tester) async {
    await prepare(tester);

    expect(find.text('Сайт'), findsOneWidget);
    expect(find.text('Активный'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Задачи'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Статистика'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('новая запись в базе сама появляется на экране', (tester) async {
    await prepare(tester);
    await openTab(tester, 'Задачи');
    expect(find.text('Задач не найдено'), findsOneWidget);

    await addTask('Появилась сама');
    await tester.pumpAndSettle();

    expect(find.text('Появилась сама'), findsOneWidget);
    expect(find.text('Задач не найдено'), findsNothing);

    await finish(tester);
  });

  testWidgets('смена статуса: история и кнопка отмены обновляются сразу',
      (tester) async {
    await prepare(tester);
    await addTask('Отчёт');
    await openTab(tester, 'Задачи');
    await tester.tap(find.text('Отчёт'));
    await tester.pumpAndSettle();
    expect(find.text('Отменить изменение статуса'), findsNothing);
    expect(find.text('История (1)'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, TaskStatus.done.label));
    await tester.pumpAndSettle();

    expect(find.text('История (2)'), findsOneWidget);

    await tester.tap(find.text('Отменить изменение статуса'));
    await tester.pumpAndSettle();

    expect(find.text('Отменить изменение статуса'), findsNothing);
    expect(find.text('История (3)'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('удалить можно только свой комментарий', (tester) async {
    await prepare(tester);
    final task = await addTask('Обсудить');
    await d.comments.addComment(taskId: task, authorId: anna, body: 'От Анны');
    await d.comments.addComment(taskId: task, authorId: boris, body: 'От Бориса');
    await openTab(tester, 'Задачи');
    await tester.tap(find.text('Обсудить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Комментарии (2)'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Удалить комментарий'), findsOneWidget);

    await tester.tap(find.byTooltip('Удалить комментарий'));
    await tester.pumpAndSettle();

    expect(find.text('От Анны'), findsNothing);
    expect(find.text('От Бориса'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('корзина: задача уходит из списка и восстанавливается',
      (tester) async {
    await prepare(tester);
    await addTask('Черновик');
    await openTab(tester, 'Задачи');
    await tester.tap(find.text('Черновик'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('В корзину'));
    await tester.pumpAndSettle();
    expect(find.text('Черновик'), findsNothing);

    await tester.tap(find.byTooltip('Корзина'));
    await tester.pumpAndSettle();
    expect(find.text('Черновик'), findsOneWidget);

    await tester.tap(find.byTooltip('Восстановить'));
    await tester.pumpAndSettle();
    expect(find.text('Корзина пуста'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Черновик'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('ошибка правила показывается пользователю', (tester) async {
    await prepare(tester);
    await addTask('Незавершённая');
    await openTab(tester, 'Люди');
    await tester.tap(find.text('Борис Ли'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Удалить пользователя'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();

    expect(
      find.text('Нельзя удалить пользователя: незавершённых задач — 1'),
      findsOneWidget,
    );

    await finish(tester);
  });

  testWidgets('форма пользователя показывает ошибку занятого email',
      (tester) async {
    await prepare(tester);
    await openTab(tester, 'Люди');
    await tester.tap(find.text('Пользователь'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'Копия');
    await tester.enterText(fields.last, 'anna@mail.kz');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(
      find.text('Пользователь с таким email уже существует'),
      findsOneWidget,
    );

    await finish(tester);
  });

  /// Заполняет форму новой задачи: проект, исполнитель и сегодняшний дедлайн.
  Future<void> fillTaskForm(WidgetTester tester, String title) async {
    await tester.enterText(find.byType(TextField).first, title);
    await tester.tap(find.text('Выберите проект'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сайт').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выберите исполнителя'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Борис Ли').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выберите дедлайн'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(DatePickerDialog));
    await tester.tap(
      find.text(MaterialLocalizations.of(context).okButtonLabel),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('форма: новая задача сохраняется и появляется в списке',
      (tester) async {
    await prepare(tester);
    await openTab(tester, 'Задачи');
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Задача'));
    await tester.pumpAndSettle();

    await fillTaskForm(tester, 'Из формы');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Новая задача'), findsNothing);
    expect(find.text('Из формы'), findsOneWidget);
    expect(find.textContaining('Сайт · Борис Ли'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('форма: без исполнителя задача не сохраняется', (tester) async {
    await prepare(tester);
    await openTab(tester, 'Задачи');
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Задача'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Неполная');
    await tester.tap(find.text('Выберите дедлайн'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(DatePickerDialog));
    await tester.tap(
      find.text(MaterialLocalizations.of(context).okButtonLabel),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Выберите проект'), findsWidgets);
    expect(find.text('Новая задача'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('форма: выбрать исполнителя можно только из участников проекта',
      (tester) async {
    await prepare(tester);
    await d.users.createUser(name: 'Чужой', email: 'other@mail.kz');
    await openTab(tester, 'Задачи');
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Задача'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выберите проект'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сайт').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выберите исполнителя'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Борис Ли'), findsOneWidget);
    expect(find.text('Чужой'), findsNothing);

    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('новый проект создаётся через форму, создатель становится Owner',
      (tester) async {
    await prepare(tester);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Проект'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Диплом');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Диплом'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Участники (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Анна Ким'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('статистика обновляется при появлении задачи', (tester) async {
    await prepare(tester);
    await openTab(tester, 'Статистика');
    expect(
      find.descendant(of: find.byType(Container), matching: find.text('0')),
      findsWidgets,
    );

    await addTask('Для статистики');
    await tester.pumpAndSettle();

    final total = find.ancestor(
      of: find.text('Всего задач'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: total.first, matching: find.text('1')),
      findsOneWidget,
    );

    await finish(tester);
  });
}
