import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/entities.dart';
import '../models/enums.dart';
import '../models/views.dart';
import '../repositories/attachment_repository.dart';
import '../repositories/comment_repository.dart';
import '../repositories/task_repository.dart';

class TaskDetailsState {
  const TaskDetailsState({
    this.task,
    this.isLoading = true,
    this.comments = const [],
    this.attachments = const [],
    this.history = const [],
  });

  final TaskView? task;
  final bool isLoading;
  final List<CommentView> comments;
  final List<Attachment> attachments;
  final List<HistoryView> history;

  bool get canUndo => TaskRepository.canUndo(history);

  TaskDetailsState copyWith({
    TaskView? Function()? task,
    List<CommentView>? comments,
    List<Attachment>? attachments,
    List<HistoryView>? history,
  }) {
    return TaskDetailsState(
      task: task == null ? this.task : task(),
      isLoading: task == null && isLoading,
      comments: comments ?? this.comments,
      attachments: attachments ?? this.attachments,
      history: history ?? this.history,
    );
  }
}

class TaskDetailsCubit extends Cubit<TaskDetailsState> {
  TaskDetailsCubit({
    required this.taskId,
    required this._tasks,
    required this._comments,
    required this._attachments,
  }) : super(const TaskDetailsState()) {
    _subscriptions.addAll([
      _tasks
          .watchTask(taskId)
          .listen((v) => emit(state.copyWith(task: () => v))),
      _tasks
          .watchHistory(taskId)
          .listen((v) => emit(state.copyWith(history: v))),
      _comments
          .watchComments(taskId)
          .listen((v) => emit(state.copyWith(comments: v))),
      _attachments
          .watchAttachments(taskId)
          .listen((v) => emit(state.copyWith(attachments: v))),
    ]);
  }

  final int taskId;
  final TaskRepository _tasks;
  final CommentRepository _comments;
  final AttachmentRepository _attachments;
  final _subscriptions = <StreamSubscription<Object?>>[];

  Future<void> changeStatus(TaskStatus status, int actorId) =>
      _tasks.changeStatus(id: taskId, status: status, actorId: actorId);

  Future<void> undoStatus(int actorId) =>
      _tasks.undoLastStatusChange(id: taskId, actorId: actorId);

  Future<void> changePriority(TaskPriority priority) =>
      _tasks.changePriority(taskId, priority);

  Future<void> reassign(int assigneeId, int actorId) =>
      _tasks.reassign(id: taskId, assigneeId: assigneeId, actorId: actorId);

  Future<void> moveToTrash() => _tasks.moveToTrash(taskId);

  Future<void> addComment(String body, int authorId) =>
      _comments.addComment(taskId: taskId, authorId: authorId, body: body);

  Future<void> deleteComment(int id, int actorId) =>
      _comments.deleteComment(id: id, actorId: actorId);

  Future<void> addAttachment(String path, String name) => _attachments
      .addAttachment(taskId: taskId, sourcePath: path, fileName: name);

  Future<void> deleteAttachment(int id) => _attachments.deleteAttachment(id);

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
