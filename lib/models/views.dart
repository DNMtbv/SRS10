import 'package:equatable/equatable.dart';

import 'entities.dart';
import 'enums.dart';

/// Задача вместе с именами, полученными через JOIN.
class TaskView {
  const TaskView({
    required this.task,
    required this.projectName,
    required this.assigneeName,
  });

  final Task task;
  final String projectName;
  final String? assigneeName;
}

class MemberView {
  const MemberView({required this.user, required this.role});

  final User user;
  final ProjectRole role;
}

class CommentView {
  const CommentView({required this.comment, required this.authorName});

  final Comment comment;
  final String? authorName;
}

class HistoryView {
  const HistoryView({
    required this.entry,
    required this.actorName,
    required this.oldAssigneeName,
    required this.newAssigneeName,
  });

  final TaskHistoryEntry entry;
  final String? actorName;
  final String? oldAssigneeName;
  final String? newAssigneeName;
}

class TaskFilter extends Equatable {
  const TaskFilter({
    this.projectId,
    this.assigneeId,
    this.status,
    this.priority,
    this.query = '',
    this.sort = TaskSort.createdDesc,
  });

  final int? projectId;
  final int? assigneeId;
  final TaskStatus? status;
  final TaskPriority? priority;
  final String query;
  final TaskSort sort;

  /// Для статуса, приоритета и исполнителя `null` значит «все», поэтому
  /// [copyWith] принимает функции: `status: () => null` сбрасывает фильтр.
  TaskFilter copyWith({
    int? Function()? assigneeId,
    TaskStatus? Function()? status,
    TaskPriority? Function()? priority,
    String? query,
    TaskSort? sort,
  }) {
    return TaskFilter(
      projectId: projectId,
      assigneeId: assigneeId == null ? this.assigneeId : assigneeId(),
      status: status == null ? this.status : status(),
      priority: priority == null ? this.priority : priority(),
      query: query ?? this.query,
      sort: sort ?? this.sort,
    );
  }

  @override
  List<Object?> get props =>
      [projectId, assigneeId, status, priority, query, sort];
}

class DashboardSummary extends Equatable {
  const DashboardSummary({
    required this.projects,
    required this.tasks,
    required this.done,
    required this.open,
    required this.cancelled,
    required this.overdue,
  });

  static const empty = DashboardSummary(
    projects: 0,
    tasks: 0,
    done: 0,
    open: 0,
    cancelled: 0,
    overdue: 0,
  );

  final int projects;
  final int tasks;
  final int done;
  final int open;
  final int cancelled;
  final int overdue;

  @override
  List<Object?> get props => [projects, tasks, done, open, cancelled, overdue];
}

class AssigneeLoad extends Equatable {
  const AssigneeLoad({required this.name, required this.tasks});

  final String name;
  final int tasks;

  @override
  List<Object?> get props => [name, tasks];
}

class ProjectProgress extends Equatable {
  const ProjectProgress({
    required this.projectId,
    required this.name,
    required this.done,
    required this.total,
  });

  final int projectId;
  final String name;
  final int done;

  /// Все задачи проекта, кроме удалённых и отменённых.
  final int total;

  int get percent => total == 0 ? 0 : (done * 100 / total).round();

  @override
  List<Object?> get props => [projectId, name, done, total];
}

class BenchmarkRow {
  const BenchmarkRow({
    required this.name,
    required this.withIndexMs,
    required this.withoutIndexMs,
    required this.planWithIndex,
    required this.planWithoutIndex,
  });

  final String name;
  final double withIndexMs;
  final double withoutIndexMs;
  final String planWithIndex;
  final String planWithoutIndex;

  double get speedup => withIndexMs == 0 ? 0 : withoutIndexMs / withIndexMs;
}
