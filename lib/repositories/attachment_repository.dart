import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../core/app_exception.dart';
import '../core/clock.dart';
import '../database/app_database.dart';
import '../models/entities.dart';

/// В базе лежит только путь, а файл копируется в папку приложения. Исходный
/// файл может исчезнуть из кэша выбора файлов, копия остаётся доступной.
class AttachmentRepository {
  AttachmentRepository(
    this._db, {
    required this._storageDirectory,
    Clock clock = systemClock,
  }) : _now = clock;

  final AppDatabase _db;
  final Future<Directory> Function() _storageDirectory;
  final Clock _now;

  Stream<List<Attachment>> watchAttachments(int taskId) =>
      (_db.select(_db.attachments)
            ..where((a) => a.taskId.equals(taskId))
            ..orderBy([(a) => OrderingTerm.desc(a.id)]))
          .watch();

  Future<int> addAttachment({
    required int taskId,
    required String sourcePath,
    String? fileName,
  }) =>
      guardDb(() async {
        final task = await (_db.select(_db.tasks)
              ..where((t) => t.id.equals(taskId) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (task == null) throw const NotFoundException('Задача не найдена');

        final source = File(sourcePath);
        if (!source.existsSync()) {
          throw const NotFoundException('Файл не найден');
        }

        final now = _now();
        final name = fileName ?? p.basename(sourcePath);
        final directory = await _storageDirectory();
        await directory.create(recursive: true);
        final stored = p.join(
          directory.path,
          '${now.microsecondsSinceEpoch}_$name',
        );
        await source.copy(stored);

        try {
          return await _db.into(_db.attachments).insert(
                AttachmentsCompanion.insert(
                  taskId: taskId,
                  fileName: name,
                  filePath: stored,
                  addedAt: now,
                ),
              );
        } catch (_) {
          await _deleteFile(stored);
          rethrow;
        }
      });

  Future<void> deleteAttachment(int id) => guardDb(() async {
        final attachment = await (_db.select(_db.attachments)
              ..where((a) => a.id.equals(id)))
            .getSingleOrNull();
        if (attachment == null) {
          throw const NotFoundException('Вложение не найдено');
        }
        await (_db.delete(_db.attachments)..where((a) => a.id.equals(id))).go();
        await _deleteFile(attachment.filePath);
      });

  /// Пути файлов задачи: читаются до удаления, потому что строки исчезнут
  /// вместе с задачей.
  Future<List<String>> pathsForTask(int taskId) async {
    final rows = await (_db.select(_db.attachments)
          ..where((a) => a.taskId.equals(taskId)))
        .get();
    return rows.map((a) => a.filePath).toList();
  }

  Future<List<String>> pathsForProject(int projectId) async {
    final query = _db.select(_db.attachments).join([
      innerJoin(_db.tasks, _db.tasks.id.equalsExp(_db.attachments.taskId)),
    ])
      ..where(_db.tasks.projectId.equals(projectId));
    final rows = await query.get();
    return rows.map((r) => r.readTable(_db.attachments).filePath).toList();
  }

  Future<void> deleteFiles(Iterable<String> paths) async {
    for (final path in paths) {
      await _deleteFile(path);
    }
  }

  Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }
}
