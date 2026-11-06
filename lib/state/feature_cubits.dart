import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/entities.dart';
import '../models/enums.dart';
import '../models/views.dart';
import '../repositories/attachment_repository.dart';
import '../repositories/maintenance_repository.dart';
import '../repositories/project_repository.dart';
import '../repositories/stats_repository.dart';
import '../repositories/task_repository.dart';
import '../repositories/user_repository.dart';
import 'watch_cubit.dart';

class UsersCubit extends WatchCubit<List<User>> {
  UsersCubit(this._users) : super(_users.watchUsers());

  final UserRepository _users;

  Future<void> create(String name, String email) =>
      _users.createUser(name: name, email: email);

  Future<void> update(int id, String name, String email) =>
      _users.updateUser(id: id, name: name, email: email);

  Future<void> delete(int id) => _users.deleteUser(id);
}

class ProjectsCubit extends WatchCubit<List<Project>> {
  ProjectsCubit(this._projects, this._attachments)
      : super(_projects.watchProjects());

  final ProjectRepository _projects;
  final AttachmentRepository _attachments;

  Future<int> create({
    required String name,
    required String description,
    required int ownerId,
    DateTime? dueDate,
  }) =>
      _projects.createProject(
        name: name,
        description: description,
        ownerId: ownerId,
        dueDate: dueDate,
      );

  Future<void> update({
    required int id,
    required String name,
    required String description,
    required ProjectStatus status,
    DateTime? dueDate,
  }) =>
      _projects.updateProject(
        id: id,
        name: name,
        description: description,
        status: status,
        dueDate: dueDate,
      );

  Future<void> delete(int id) async {
    final paths = await _attachments.pathsForProject(id);
    await _projects.deleteProject(id);
    await _attachments.deleteFiles(paths);
  }
}

class ProjectDetailsState {
  const ProjectDetailsState({
    this.project,
    this.members = const [],
    this.isLoading = true,
  });

  final Project? project;
  final List<MemberView> members;
  final bool isLoading;
}

class ProjectDetailsCubit extends Cubit<ProjectDetailsState> {
  ProjectDetailsCubit(this._projects, this.projectId)
      : super(const ProjectDetailsState()) {
    _subscriptions.addAll([
      _projects.watchProject(projectId).listen(
            (project) => emit(
              ProjectDetailsState(
                project: project,
                members: state.members,
                isLoading: false,
              ),
            ),
          ),
      _projects.watchMembers(projectId).listen(
            (members) => emit(
              ProjectDetailsState(
                project: state.project,
                members: members,
                isLoading: state.isLoading,
              ),
            ),
          ),
    ]);
  }

  final ProjectRepository _projects;
  final int projectId;
  final _subscriptions = <StreamSubscription<Object?>>[];

  Future<void> addMember(int userId, ProjectRole role) => _projects.addMember(
        projectId: projectId,
        userId: userId,
        role: role,
      );

  Future<void> removeMember(int userId) =>
      _projects.removeMember(projectId: projectId, userId: userId);

  Future<void> changeRole(int userId, ProjectRole role) => _projects.changeRole(
        projectId: projectId,
        userId: userId,
        role: role,
      );

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}

class TrashCubit extends WatchCubit<List<TaskView>> {
  TrashCubit(this._tasks, this._attachments) : super(_tasks.watchTrash());

  final TaskRepository _tasks;
  final AttachmentRepository _attachments;

  Future<void> restore(int id) => _tasks.restore(id);

  Future<void> deletePermanently(int id) async {
    final paths = await _attachments.pathsForTask(id);
    await _tasks.deletePermanently(id);
    await _attachments.deleteFiles(paths);
  }
}

class DashboardState {
  const DashboardState({
    this.summary = DashboardSummary.empty,
    this.byPriority = const {},
    this.byAssignee = const [],
    this.progress = const [],
  });

  final DashboardSummary summary;
  final Map<TaskPriority, int> byPriority;
  final List<AssigneeLoad> byAssignee;
  final List<ProjectProgress> progress;

  DashboardState copyWith({
    DashboardSummary? summary,
    Map<TaskPriority, int>? byPriority,
    List<AssigneeLoad>? byAssignee,
    List<ProjectProgress>? progress,
  }) {
    return DashboardState(
      summary: summary ?? this.summary,
      byPriority: byPriority ?? this.byPriority,
      byAssignee: byAssignee ?? this.byAssignee,
      progress: progress ?? this.progress,
    );
  }
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(StatsRepository stats) : super(const DashboardState()) {
    _subscriptions.addAll([
      stats.watchSummary().listen((v) => emit(state.copyWith(summary: v))),
      stats.watchByPriority().listen((v) => emit(state.copyWith(byPriority: v))),
      stats.watchByAssignee().listen((v) => emit(state.copyWith(byAssignee: v))),
      stats
          .watchProjectProgress()
          .listen((v) => emit(state.copyWith(progress: v))),
    ]);
  }

  final _subscriptions = <StreamSubscription<Object?>>[];

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}

class ToolsState {
  const ToolsState({this.busy, this.results = const []});

  /// Что выполняется сейчас, для текста на экране.
  final String? busy;
  final List<BenchmarkRow> results;
}

class ToolsCubit extends Cubit<ToolsState> {
  ToolsCubit(this._maintenance) : super(const ToolsState());

  final MaintenanceRepository _maintenance;

  Future<void> _run(String label, Future<void> Function() action) async {
    emit(ToolsState(busy: label, results: state.results));
    try {
      await action();
    } finally {
      emit(ToolsState(results: state.results));
    }
  }

  Future<void> seedDemo() =>
      _run('Создаю демо-данные…', _maintenance.seedDemo);

  Future<void> seedLarge() =>
      _run('Создаю 10 000 задач…', _maintenance.seedLarge);

  Future<void> clearAll() => _run('Очищаю базу…', _maintenance.clearAll);

  Future<void> runBenchmark() async {
    emit(ToolsState(busy: 'Сравниваю скорость…', results: state.results));
    try {
      final rows = await _maintenance.runBenchmark();
      emit(ToolsState(results: rows));
    } catch (_) {
      emit(ToolsState(results: state.results));
      rethrow;
    }
  }
}
