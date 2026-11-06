import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/entities.dart';
import '../../models/enums.dart';
import '../../models/views.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/task_repository.dart';
import '../../state/feature_cubits.dart';
import '../common.dart';

Future<void> openTaskForm(
  BuildContext context, {
  Project? project,
  Task? task,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => _TaskFormScreen(project: project, task: task),
    ),
  );
}

class _TaskFormScreen extends StatefulWidget {
  const _TaskFormScreen({this.project, this.task});

  final Project? project;
  final Task? task;

  @override
  State<_TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<_TaskFormScreen> {
  late final _title = TextEditingController(text: widget.task?.title);
  late final _description =
      TextEditingController(text: widget.task?.description);
  late TaskPriority _priority = widget.task?.priority ?? TaskPriority.medium;
  late DateTime? _deadline = widget.task?.deadline;
  late Project? _project = widget.project;
  User? _assignee;

  bool get _editing => widget.task != null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickProject() async {
    final projects =
        context.read<ProjectsCubit>().state.data ?? const <Project>[];
    final picked = await showModalBottomSheet<Project>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (final project in projects)
            ListTile(
              title: Text(project.name),
              onTap: () => Navigator.pop(context, project),
            ),
        ],
      ),
    );
    if (picked != null) {
      setState(() {
        _project = picked;
        _assignee = null;
      });
    }
  }

  /// Выбрать можно только участников проекта.
  Future<void> _pickAssignee() async {
    final project = _project;
    if (project == null) return _hint('Сначала выберите проект');
    final members =
        await context.read<ProjectRepository>().getMembers(project.id);
    if (!mounted) return;
    final user = await pickUser(
      context,
      users: members.map((MemberView m) => m.user).toList(),
      title: 'Участники проекта',
    );
    if (user != null) setState(() => _assignee = user);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  void _hint(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    final tasks = context.read<TaskRepository>();
    final navigator = Navigator.of(context);
    final deadline = _deadline;
    if (deadline == null) return _hint('Укажите дедлайн');

    final task = widget.task;
    if (task != null) {
      final ok = await guarded(
        context,
        () => tasks.updateTask(
          id: task.id,
          title: _title.text,
          description: _description.text,
          priority: _priority,
          deadline: deadline,
        ),
      );
      if (ok) navigator.pop();
      return;
    }

    final project = _project;
    final assignee = _assignee;
    if (project == null) return _hint('Выберите проект');
    if (assignee == null) return _hint('Выберите исполнителя');
    final actor = actorOf(context);
    if (actor == null) return;
    final ok = await guarded(
      context,
      () => tasks.createTask(
        title: _title.text,
        description: _description.text,
        projectId: project.id,
        assigneeId: assignee.id,
        priority: _priority,
        deadline: deadline,
        actorId: actor,
      ),
    );
    if (ok) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = _deadline;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Изменить задачу' : 'Новая задача')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Описание'),
          ),
          if (!_editing) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined),
              title: Text(_project?.name ?? 'Выберите проект'),
              enabled: widget.project == null,
              onTap: _pickProject,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(_assignee?.name ?? 'Выберите исполнителя'),
              onTap: _pickAssignee,
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(
              deadline == null
                  ? 'Выберите дедлайн'
                  : 'Дедлайн: ${formatDate(deadline)}',
            ),
            onTap: _pickDeadline,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<TaskPriority>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Приоритет'),
            items: [
              for (final priority in TaskPriority.values)
                DropdownMenuItem(value: priority, child: Text(priority.label)),
            ],
            onChanged: (value) => setState(() => _priority = value!),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Сохранить')),
        ],
      ),
    );
  }
}
