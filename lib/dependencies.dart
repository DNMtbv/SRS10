import 'dart:io';

import 'core/clock.dart';
import 'database/app_database.dart';
import 'repositories/attachment_repository.dart';
import 'repositories/comment_repository.dart';
import 'repositories/maintenance_repository.dart';
import 'repositories/project_repository.dart';
import 'repositories/stats_repository.dart';
import 'repositories/task_repository.dart';
import 'repositories/user_repository.dart';

/// Все репозитории приложения. Создаются один раз на старте.
class Dependencies {
  Dependencies({
    required AppDatabase database,
    required Future<Directory> Function() attachmentsDirectory,
    required Future<Directory> Function() temporaryDirectory,
    Clock clock = systemClock,
  })  : users = UserRepository(database, clock: clock),
        projects = ProjectRepository(database, clock: clock),
        tasks = TaskRepository(database, clock: clock),
        comments = CommentRepository(database, clock: clock),
        stats = StatsRepository(database, clock: clock),
        attachments = AttachmentRepository(
          database,
          storageDirectory: attachmentsDirectory,
          clock: clock,
        ) {
    maintenance = MaintenanceRepository(
      database,
      attachments: attachments,
      temporaryDirectory: temporaryDirectory,
      clock: clock,
    );
  }

  final UserRepository users;
  final ProjectRepository projects;
  final TaskRepository tasks;
  final CommentRepository comments;
  final StatsRepository stats;
  final AttachmentRepository attachments;
  late final MaintenanceRepository maintenance;
}
