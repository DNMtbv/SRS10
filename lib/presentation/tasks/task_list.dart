import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/clock.dart';
import '../../models/entities.dart';
import '../../models/enums.dart';
import '../../models/views.dart';
import '../../state/feature_cubits.dart';
import '../../state/tasks_cubit.dart';
import '../common.dart';
import 'task_details_screen.dart';

/// Список с поиском, фильтрами, сортировкой и подгрузкой страниц.
/// Набор задач задаёт [TasksCubit] выше по дереву: все, проект или исполнитель.
class TaskList extends StatefulWidget {
  const TaskList({super.key});

  @override
  State<TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<TaskList>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) {
        context.read<TasksCubit>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        const _Filters(),
        Expanded(
          child: BlocBuilder<TasksCubit, TasksState>(
            builder: (context, state) {
              if (state.isLoading && state.items.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.items.isEmpty) {
                return const EmptyView(
                  icon: Icons.task_alt,
                  text: 'Задач не найдено',
                );
              }
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: state.items.length + (state.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == state.items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return TaskTile(view: state.items[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TasksCubit>();
    return BlocBuilder<TasksCubit, TasksState>(
      buildWhen: (a, b) => a.filter != b.filter,
      builder: (context, state) {
        final filter = state.filter;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Поиск по названию и описанию',
                ),
                onChanged: cubit.setQuery,
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 8,
                  children: [
                    _Menu<TaskStatus>(
                      label: filter.status?.label ?? 'Статус',
                      active: filter.status != null,
                      values: TaskStatus.values,
                      title: (v) => v.label,
                      onSelected: cubit.setStatus,
                    ),
                    _Menu<TaskPriority>(
                      label: filter.priority?.label ?? 'Приоритет',
                      active: filter.priority != null,
                      values: TaskPriority.values,
                      title: (v) => v.label,
                      onSelected: cubit.setPriority,
                    ),
                    FilterChip(
                      label: Text(
                        filter.assigneeId == null ? 'Исполнитель' : 'Выбран',
                      ),
                      selected: filter.assigneeId != null,
                      onSelected: (_) => _pickAssignee(context, filter),
                    ),
                    PopupMenuButton<TaskSort>(
                      tooltip: 'Сортировка',
                      onSelected: cubit.setSort,
                      itemBuilder: (_) => [
                        for (final sort in TaskSort.values)
                          CheckedPopupMenuItem(
                            value: sort,
                            checked: sort == filter.sort,
                            child: Text(sort.label),
                          ),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.sort, size: 18),
                        label: Text(filter.sort.label),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAssignee(BuildContext context, TaskFilter filter) async {
    final cubit = context.read<TasksCubit>();
    if (filter.assigneeId != null) {
      cubit.setAssignee(null);
      return;
    }
    final users = context.read<UsersCubit>().state.data ?? const <User>[];
    final user = await pickUser(context, users: users, title: 'Исполнитель');
    if (user != null) cubit.setAssignee(user.id);
  }
}

class _Menu<T> extends StatelessWidget {
  const _Menu({
    required this.label,
    required this.active,
    required this.values,
    required this.title,
    required this.onSelected,
  });

  final String label;
  final bool active;
  final List<T> values;
  final String Function(T) title;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: label,
      onSelected: (index) => onSelected(index < 0 ? null : values[index]),
      itemBuilder: (_) => [
        const PopupMenuItem(value: -1, child: Text('Все')),
        for (final (index, value) in values.indexed)
          PopupMenuItem(value: index, child: Text(title(value))),
      ],
      child: Chip(
        label: Text(label),
        backgroundColor:
            active ? Theme.of(context).colorScheme.secondaryContainer : null,
      ),
    );
  }
}

class TaskTile extends StatelessWidget {
  const TaskTile({required this.view, this.trailing, this.onTap, super.key});

  final TaskView view;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final task = view.task;
    final overdue = task.status.isOpen &&
        task.deadline.isBefore(startOfDay(DateTime.now()));
    return ListTile(
      title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${view.projectName} · ${view.assigneeName ?? 'Без исполнителя'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tag(text: task.status.label, color: statusColor(task.status)),
              Tag(
                text: task.priority.label,
                color: priorityColor(task.priority),
              ),
              Text(
                formatDate(task.deadline),
                style: TextStyle(
                  fontSize: 12,
                  color: overdue ? Theme.of(context).colorScheme.error : null,
                  fontWeight: overdue ? FontWeight.w700 : null,
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: trailing,
      onTap: onTap ?? () => openTaskDetails(context, task.id),
    );
  }
}
