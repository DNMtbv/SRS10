import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/enums.dart';
import '../repositories/stats_repository.dart';
import '../state/feature_cubits.dart';
import 'common.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DashboardCubit(context.read<StatsRepository>()),
      child: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) {
          final s = state.summary;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  childAspectRatio: 2.3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    _Stat('Проекты', s.projects),
                    _Stat('Всего задач', s.tasks),
                    _Stat('Завершено', s.done),
                    _Stat('Не завершено', s.open),
                    _Stat('Просрочено', s.overdue, alert: s.overdue > 0),
                    _Stat('Отменено', s.cancelled),
                  ],
                ),
              ),
              const _Header('Задачи по приоритетам'),
              SliverList.list(
                children: [
                  for (final priority in TaskPriority.values)
                    ListTile(
                      dense: true,
                      leading: Tag(
                        text: priority.label,
                        color: priorityColor(priority),
                      ),
                      trailing: Text('${state.byPriority[priority] ?? 0}'),
                    ),
                ],
              ),
              const _Header('Выполнение проектов'),
              SliverList.builder(
                itemCount: state.progress.length,
                itemBuilder: (context, index) {
                  final project = state.progress[index];
                  return ListTile(
                    dense: true,
                    title: Text(project.name),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(
                        value: project.percent / 100,
                      ),
                    ),
                    trailing: Text('${project.percent} %'),
                  );
                },
              ),
              const _Header('Задачи у исполнителей'),
              SliverList.builder(
                itemCount: state.byAssignee.length,
                itemBuilder: (context, index) {
                  final item = state.byAssignee[index];
                  return ListTile(
                    dense: true,
                    title: Text(item.name),
                    trailing: Text('${item.tasks}'),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.alert = false});

  final String label;
  final int value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: alert ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
