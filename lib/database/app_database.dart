import 'package:drift/drift.dart';

import '../models/entities.dart';
import '../models/enums.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Users,
    Projects,
    ProjectMembers,
    Tasks,
    Comments,
    Attachments,
    TaskHistory,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.connection);

  /// Версия 1: в таблице tasks нет поля priority.
  /// Версия 2: добавлено поле priority со значением medium для старых задач.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // DEFAULT 'medium' сразу заполняет поле у всех существующих строк.
            await m.addColumn(tasks, tasks.priority);
            await m.createIndex(idxTasksPriorityCreated);
          }
        },
        // SQLite по умолчанию не проверяет внешние ключи.
        beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
      );
}
