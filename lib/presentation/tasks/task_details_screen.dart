import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/entities.dart';
import '../../models/enums.dart';
import '../../models/views.dart';
import '../../repositories/attachment_repository.dart';
import '../../repositories/comment_repository.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/task_repository.dart';
import '../../state/session_cubit.dart';
import '../../state/task_details_cubit.dart';
import '../common.dart';
import 'task_form_screen.dart';

Future<void> openTaskDetails(BuildContext context, int taskId) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => BlocProvider(
        create: (context) => TaskDetailsCubit(
          taskId: taskId,
          tasks: context.read<TaskRepository>(),
          comments: context.read<CommentRepository>(),
          attachments: context.read<AttachmentRepository>(),
        ),
        child: const _TaskDetailsScreen(),
      ),
    ),
  );
}

class _TaskDetailsScreen extends StatelessWidget {
  const _TaskDetailsScreen();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TaskDetailsCubit, TaskDetailsState>(
      builder: (context, state) {
        final view = state.task;
        if (view == null) {
          return Scaffold(
            appBar: AppBar(),
            body: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : const EmptyView(
                    icon: Icons.search_off,
                    text: 'Задача удалена',
                  ),
          );
        }
        final deleted = view.task.deletedAt != null;
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Задача'),
              actions: [
                if (!deleted) ...[
                  IconButton(
                    tooltip: 'Изменить',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => openTaskForm(context, task: view.task),
                  ),
                  IconButton(
                    tooltip: 'В корзину',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _moveToTrash(context),
                  ),
                ],
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  const Tab(text: 'Детали'),
                  Tab(text: 'Комментарии (${state.comments.length})'),
                  Tab(text: 'Файлы (${state.attachments.length})'),
                  Tab(text: 'История (${state.history.length})'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _DetailsTab(view: view, canUndo: state.canUndo),
                _CommentsTab(comments: state.comments),
                _AttachmentsTab(attachments: state.attachments),
                _HistoryTab(history: state.history),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _moveToTrash(BuildContext context) async {
    final cubit = context.read<TaskDetailsCubit>();
    final navigator = Navigator.of(context);
    final ok = await guarded(context, cubit.moveToTrash);
    if (ok) navigator.pop();
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.view, required this.canUndo});

  final TaskView view;
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TaskDetailsCubit>();
    final task = view.task;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(task.title, style: theme.textTheme.headlineSmall),
        if (task.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(task.description),
        ],
        const SizedBox(height: 16),
        Text('Статус', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final status in TaskStatus.values)
              ChoiceChip(
                label: Text(status.label),
                selected: status == task.status,
                onSelected: (_) {
                  final actor = actorOf(context);
                  if (actor == null) return;
                  guarded(context, () => cubit.changeStatus(status, actor));
                },
              ),
          ],
        ),
        if (canUndo)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.undo),
              label: const Text('Отменить изменение статуса'),
              onPressed: () {
                final actor = actorOf(context);
                if (actor == null) return;
                guarded(context, () => cubit.undoStatus(actor));
              },
            ),
          ),
        const SizedBox(height: 8),
        DropdownButtonFormField<TaskPriority>(
          key: ValueKey(task.priority),
          initialValue: task.priority,
          decoration: const InputDecoration(labelText: 'Приоритет'),
          items: [
            for (final priority in TaskPriority.values)
              DropdownMenuItem(value: priority, child: Text(priority.label)),
          ],
          onChanged: (value) {
            if (value != null) {
              guarded(context, () => cubit.changePriority(value));
            }
          },
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(view.assigneeName ?? 'Без исполнителя'),
          subtitle: const Text('Исполнитель, нажмите, чтобы сменить'),
          onTap: () => _reassign(context, task),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_outlined),
          title: Text(view.projectName),
          subtitle: const Text('Проект'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text(formatDate(task.deadline)),
          subtitle: const Text('Дедлайн'),
        ),
        Text(
          'Создана ${formatDateTime(task.createdAt)}\n'
          'Изменена ${formatDateTime(task.updatedAt)}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _reassign(BuildContext context, Task task) async {
    final cubit = context.read<TaskDetailsCubit>();
    final members =
        await context.read<ProjectRepository>().getMembers(task.projectId);
    if (!context.mounted) return;
    final user = await pickUser(
      context,
      users: members.map((m) => m.user).toList(),
      title: 'Новый исполнитель',
    );
    if (user == null || !context.mounted) return;
    final actor = actorOf(context);
    if (actor == null) return;
    await guarded(context, () => cubit.reassign(user.id, actor));
  }
}

class _CommentsTab extends StatefulWidget {
  const _CommentsTab({required this.comments});

  final List<CommentView> comments;

  @override
  State<_CommentsTab> createState() => _CommentsTabState();
}

class _CommentsTabState extends State<_CommentsTab> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final cubit = context.read<TaskDetailsCubit>();
    final actor = actorOf(context);
    if (actor == null) return;
    final ok = await guarded(context, () => cubit.addComment(_text.text, actor));
    if (ok) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TaskDetailsCubit>();
    final me = context.watch<SessionCubit>().state?.id;
    return Column(
      children: [
        Expanded(
          child: widget.comments.isEmpty
              ? const EmptyView(
                  icon: Icons.forum_outlined,
                  text: 'Комментариев пока нет',
                )
              : ListView.builder(
                  itemCount: widget.comments.length,
                  itemBuilder: (context, index) {
                    final item = widget.comments[index];
                    final mine = item.comment.authorId == me;
                    return ListTile(
                      title: Text(item.comment.body),
                      subtitle: Text(
                        '${item.authorName ?? 'Удалённый пользователь'} · '
                        '${formatDateTime(item.comment.createdAt)}',
                      ),
                      trailing: mine
                          ? IconButton(
                              tooltip: 'Удалить комментарий',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => guarded(
                                context,
                                () => cubit.deleteComment(item.comment.id, me!),
                              ),
                            )
                          : null,
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    decoration: const InputDecoration(
                      hintText: 'Комментарий',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Отправить',
                  icon: const Icon(Icons.send),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AttachmentsTab extends StatelessWidget {
  const _AttachmentsTab({required this.attachments});

  final List<Attachment> attachments;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TaskDetailsCubit>();
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.attach_file),
          title: const Text('Прикрепить файл'),
          onTap: () => _pick(context),
        ),
        const Divider(height: 1),
        for (final item in attachments)
          ListTile(
            leading: Icon(
              File(item.filePath).existsSync()
                  ? Icons.insert_drive_file_outlined
                  : Icons.broken_image_outlined,
            ),
            title: Text(item.fileName),
            subtitle: Text(
              '${formatDateTime(item.addedAt)}\n${item.filePath}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Удалить файл',
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  guarded(context, () => cubit.deleteAttachment(item.id)),
            ),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final cubit = context.read<TaskDetailsCubit>();
    final files = await FilePicker.pickFiles();
    final file = files.firstOrNull;
    final path = file?.path;
    if (file == null || path == null || !context.mounted) return;
    await guarded(context, () => cubit.addAttachment(path, file.name));
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.history});

  final List<HistoryView> history;

  String _describe(HistoryView item) {
    final entry = item.entry;
    return switch (entry.event) {
      HistoryEvent.created => entry.event.label,
      HistoryEvent.reassigned =>
        '${item.oldAssigneeName ?? 'Без исполнителя'} → '
            '${item.newAssigneeName ?? 'Без исполнителя'}',
      _ => '${entry.oldStatus?.label} → ${entry.newStatus?.label}',
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[index];
        return ListTile(
          leading: Icon(switch (item.entry.event) {
            HistoryEvent.created => Icons.add_circle_outline,
            HistoryEvent.statusChanged => Icons.swap_horiz,
            HistoryEvent.statusUndone => Icons.undo,
            HistoryEvent.reassigned => Icons.person_outline,
          }),
          title: Text(_describe(item)),
          subtitle: Text(
            [
              if (item.entry.event != HistoryEvent.created)
                item.entry.event.label,
              item.actorName ?? 'Удалённый пользователь',
              formatDateTime(item.entry.changedAt),
            ].join(' · '),
          ),
        );
      },
    );
  }
}
