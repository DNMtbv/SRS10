import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:taskflow/core/app_exception.dart';

import 'helpers/world.dart';

void main() {
  late World w;

  setUp(() async => w = await World.create());

  group('комментарии', () {
    test('добавление и просмотр: текст, автор, задача и дата', () async {
      final task = await w.task();

      await w.comments.addComment(
        taskId: task,
        authorId: w.boris,
        body: '  Готово  ',
      );

      final item = (await w.comments.watchComments(task).first).single;
      expect(item.comment.body, 'Готово');
      expect(item.comment.taskId, task);
      expect(item.comment.createdAt, w.now);
      expect(item.authorName, 'Борис Ли');
    });

    test('комментарий к несуществующей задаче запрещён', () async {
      await expectLater(
        w.comments.addComment(taskId: 999, authorId: w.anna, body: 'Текст'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('пустой комментарий не сохраняется', () async {
      final task = await w.task();
      expect(
        () => w.comments.addComment(taskId: task, authorId: w.anna, body: '  '),
        throwsA(isA<ValidationException>()),
      );
    });

    test('удалить комментарий может только автор', () async {
      final task = await w.task();
      final id = await w.comments.addComment(
        taskId: task,
        authorId: w.boris,
        body: 'Текст',
      );

      await expectLater(
        w.comments.deleteComment(id: id, actorId: w.anna),
        throwsA(isA<RuleViolationException>()),
      );
      expect(await w.comments.watchComments(task).first, hasLength(1));

      await w.comments.deleteComment(id: id, actorId: w.boris);
      expect(await w.comments.watchComments(task).first, isEmpty);
    });

    test('комментарий остаётся после удаления автора', () async {
      final task = await w.task(assignee: w.anna);
      await w.projects.addMember(projectId: w.project, userId: w.outsider);
      await w.comments.addComment(
        taskId: task,
        authorId: w.outsider,
        body: 'Текст',
      );

      await w.users.deleteUser(w.outsider);

      final item = (await w.comments.watchComments(task).first).single;
      expect(item.authorName, isNull);
    });
  });

  group('вложения', () {
    late File source;

    setUp(() async {
      source = File(p.join(w.files.path, 'source', 'отчёт.txt'));
      await source.create(recursive: true);
      await source.writeAsString('содержимое файла');
    });

    test('в базе путь и название, содержимое лежит в отдельном файле',
        () async {
      final task = await w.task();

      await w.attachments.addAttachment(
        taskId: task,
        sourcePath: source.path,
      );

      final item = (await w.attachments.watchAttachments(task).first).single;
      expect(item.taskId, task);
      expect(item.fileName, 'отчёт.txt');
      expect(item.addedAt, w.now);
      expect(item.filePath, isNot(source.path));
      expect(await File(item.filePath).readAsString(), 'содержимое файла');
    });

    test('схема таблицы хранит только текстовый путь', () async {
      final columns =
          await w.db.customSelect('PRAGMA table_info(attachments)').get();
      expect(
        columns.map((c) => c.read<String>('type')),
        everyElement(isNot('BLOB')),
      );
    });

    test('нельзя прикрепить файл к несуществующей задаче', () async {
      await expectLater(
        w.attachments.addAttachment(taskId: 999, sourcePath: source.path),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('нельзя прикрепить несуществующий файл', () async {
      final task = await w.task();
      await expectLater(
        w.attachments.addAttachment(taskId: task, sourcePath: 'нет/файла.txt'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('удаление вложения удаляет строку и копию файла', () async {
      final task = await w.task();
      final id = await w.attachments.addAttachment(
        taskId: task,
        sourcePath: source.path,
      );
      final stored =
          (await w.attachments.watchAttachments(task).first).single.filePath;

      await w.attachments.deleteAttachment(id);

      expect(await w.attachments.watchAttachments(task).first, isEmpty);
      expect(File(stored).existsSync(), isFalse);
      expect(source.existsSync(), isTrue);
    });

    test('каскад: полное удаление задачи убирает строки вложений', () async {
      final task = await w.task();
      await w.attachments.addAttachment(taskId: task, sourcePath: source.path);
      final paths = await w.attachments.pathsForTask(task);
      await w.tasks.moveToTrash(task);

      await w.tasks.deletePermanently(task);
      await w.attachments.deleteFiles(paths);

      expect(await w.attachments.watchAttachments(task).first, isEmpty);
      expect(File(paths.single).existsSync(), isFalse);
    });
  });
}
