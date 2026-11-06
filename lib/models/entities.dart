import 'enums.dart';

/// Строки таблиц. Drift заполняет эти классы сам (см. `@UseRowClass`),
/// поэтому остальной код не зависит от сгенерированных файлов.
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.registeredAt,
  });

  final int id;
  final String name;
  final String email;
  final DateTime registeredAt;
}

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.dueDate,
    required this.status,
  });

  final int id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime? dueDate;
  final ProjectStatus status;
}

class ProjectMember {
  const ProjectMember({
    required this.projectId,
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  final int projectId;
  final int userId;
  final ProjectRole role;
  final DateTime joinedAt;
}

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.description,
    required this.searchText,
    required this.projectId,
    required this.assigneeId,
    required this.priority,
    required this.status,
    required this.deadline,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final int id;
  final String title;
  final String description;

  /// Название и описание в нижнем регистре, нужны только для поиска.
  final String searchText;
  final int projectId;
  final int? assigneeId;
  final TaskPriority priority;
  final TaskStatus status;
  final DateTime deadline;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft Delete: если поле заполнено, задача лежит в корзине.
  final DateTime? deletedAt;
}

class Comment {
  const Comment({
    required this.id,
    required this.taskId,
    required this.authorId,
    required this.body,
    required this.createdAt,
  });

  final int id;
  final int taskId;
  final int? authorId;
  final String body;
  final DateTime createdAt;
}

class Attachment {
  const Attachment({
    required this.id,
    required this.taskId,
    required this.fileName,
    required this.filePath,
    required this.addedAt,
  });

  final int id;
  final int taskId;
  final String fileName;
  final String filePath;
  final DateTime addedAt;
}

class TaskHistoryEntry {
  const TaskHistoryEntry({
    required this.id,
    required this.taskId,
    required this.event,
    required this.oldStatus,
    required this.newStatus,
    required this.oldAssigneeId,
    required this.newAssigneeId,
    required this.changedBy,
    required this.changedAt,
  });

  final int id;
  final int taskId;
  final HistoryEvent event;
  final TaskStatus? oldStatus;
  final TaskStatus? newStatus;
  final int? oldAssigneeId;
  final int? newAssigneeId;
  final int? changedBy;
  final DateTime changedAt;
}

class AppSetting {
  const AppSetting({required this.key, required this.value});

  final String key;
  final String value;
}
