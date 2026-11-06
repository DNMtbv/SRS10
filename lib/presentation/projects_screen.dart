import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/entities.dart';
import '../models/enums.dart';
import '../models/views.dart';
import '../repositories/project_repository.dart';
import '../repositories/task_repository.dart';
import '../state/feature_cubits.dart';
import '../state/tasks_cubit.dart';
import '../state/watch_cubit.dart';
import 'common.dart';
import 'tasks/task_form_screen.dart';
import 'tasks/task_list.dart';

Future<void> openProjectForm(BuildContext context, {Project? project}) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => _ProjectFormScreen(project: project),
    ),
  );
}

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProjectsCubit, WatchState<List<Project>>>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final projects = state.data ?? const <Project>[];
        if (projects.isEmpty) {
          return const EmptyView(
            icon: Icons.folder_open,
            text: 'Проектов пока нет.\nДля примера откройте Инструменты → '
                'Демо-данные.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final project = projects[index];
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(project.name),
              subtitle: Text(
                project.description.isEmpty
                    ? 'Создан ${formatDate(project.createdAt)}'
                    : project.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Tag(
                text: project.status.label,
                color: Theme.of(context).colorScheme.primary,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MultiBlocProvider(
                    providers: [
                      BlocProvider(
                        create: (context) => ProjectDetailsCubit(
                          context.read<ProjectRepository>(),
                          project.id,
                        ),
                      ),
                      BlocProvider(
                        create: (context) => TasksCubit(
                          context.read<TaskRepository>(),
                          filter: TaskFilter(projectId: project.id),
                        ),
                      ),
                    ],
                    child: const _ProjectDetailsScreen(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ProjectDetailsScreen extends StatelessWidget {
  const _ProjectDetailsScreen();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProjectDetailsCubit, ProjectDetailsState>(
      builder: (context, state) {
        final project = state.project;
        if (project == null) {
          return Scaffold(
            appBar: AppBar(),
            body: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : const EmptyView(
                    icon: Icons.folder_off_outlined,
                    text: 'Проект удалён',
                  ),
          );
        }
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(project.name),
              actions: [
                IconButton(
                  tooltip: 'Изменить',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => openProjectForm(context, project: project),
                ),
                IconButton(
                  tooltip: 'Удалить проект',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(context, project),
                ),
              ],
              bottom: TabBar(
                tabs: [
                  const Tab(text: 'Задачи'),
                  Tab(text: 'Участники (${state.members.length})'),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              heroTag: 'project_task',
              icon: const Icon(Icons.add),
              label: const Text('Задача'),
              onPressed: () => openTaskForm(context, project: project),
            ),
            body: const TabBarView(children: [TaskList(), _MembersTab()]),
          ),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, Project project) async {
    final cubit = context.read<ProjectsCubit>();
    final navigator = Navigator.of(context);
    final yes = await confirm(
      context,
      title: 'Удалить проект?',
      message: 'Вместе с «${project.name}» удалятся все его задачи, '
          'комментарии, вложения и история.',
    );
    if (!yes || !context.mounted) return;
    final ok = await guarded(context, () => cubit.delete(project.id));
    if (ok) navigator.pop();
  }
}

class _MembersTab extends StatelessWidget {
  const _MembersTab();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProjectDetailsCubit>();
    return BlocBuilder<ProjectDetailsCubit, ProjectDetailsState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Добавить участника'),
              onTap: () => _add(context, state.members),
            ),
            const Divider(height: 1),
            for (final member in state.members)
              ListTile(
                title: Text(member.user.name),
                subtitle: Text(member.user.email),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<ProjectRole>(
                      value: member.role,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final role in ProjectRole.values)
                          DropdownMenuItem(
                            value: role,
                            child: Text(role.label),
                          ),
                      ],
                      onChanged: (role) {
                        if (role == null) return;
                        guarded(
                          context,
                          () => cubit.changeRole(member.user.id, role),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'Убрать из проекта',
                      icon: const Icon(Icons.close),
                      onPressed: () => guarded(
                        context,
                        () => cubit.removeMember(member.user.id),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _add(BuildContext context, List<MemberView> members) async {
    final cubit = context.read<ProjectDetailsCubit>();
    final taken = members.map((m) => m.user.id).toSet();
    final users = (context.read<UsersCubit>().state.data ?? const <User>[])
        .where((u) => !taken.contains(u.id))
        .toList();
    final user = await pickUser(context, users: users, title: 'Новый участник');
    if (user == null || !context.mounted) return;
    await guarded(
      context,
      () => cubit.addMember(user.id, ProjectRole.member),
    );
  }
}

class _ProjectFormScreen extends StatefulWidget {
  const _ProjectFormScreen({this.project});

  final Project? project;

  @override
  State<_ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<_ProjectFormScreen> {
  late final _name = TextEditingController(text: widget.project?.name);
  late final _description =
      TextEditingController(text: widget.project?.description);
  late DateTime? _dueDate = widget.project?.dueDate;
  late ProjectStatus _status = widget.project?.status ?? ProjectStatus.active;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    final cubit = context.read<ProjectsCubit>();
    final navigator = Navigator.of(context);
    final project = widget.project;
    final bool ok;
    if (project != null) {
      ok = await guarded(
        context,
        () => cubit.update(
          id: project.id,
          name: _name.text,
          description: _description.text,
          status: _status,
          dueDate: _dueDate,
        ),
      );
    } else {
      // Создатель проекта становится его Owner.
      final owner = actorOf(context);
      if (owner == null) return;
      ok = await guarded(
        context,
        () => cubit.create(
          name: _name.text,
          description: _description.text,
          ownerId: owner,
          dueDate: _dueDate,
        ),
      );
    }
    if (ok) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.project != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Изменить проект' : 'Новый проект')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Описание'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(
              _dueDate == null
                  ? 'Дата завершения не указана'
                  : 'Дата завершения: ${formatDate(_dueDate!)}',
            ),
            trailing: _dueDate == null
                ? null
                : IconButton(
                    tooltip: 'Убрать дату',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _dueDate = null),
                  ),
            onTap: _pickDate,
          ),
          if (editing) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<ProjectStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Статус'),
              items: [
                for (final status in ProjectStatus.values)
                  DropdownMenuItem(value: status, child: Text(status.label)),
              ],
              onChanged: (value) => setState(() => _status = value!),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Сохранить')),
        ],
      ),
    );
  }
}
