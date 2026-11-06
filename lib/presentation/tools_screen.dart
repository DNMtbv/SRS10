import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/views.dart';
import '../repositories/maintenance_repository.dart';
import '../state/feature_cubits.dart';
import 'common.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ToolsCubit(context.read<MaintenanceRepository>()),
      child: Scaffold(
        appBar: AppBar(title: const Text('Инструменты')),
        body: BlocBuilder<ToolsCubit, ToolsState>(
          builder: (context, state) {
            final cubit = context.read<ToolsCubit>();
            final busy = state.busy != null;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (busy) ...[
                  const LinearProgressIndicator(),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(state.busy!),
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Демо-данные'),
                  subtitle: const Text('3 пользователя, 2 проекта, 5 задач'),
                  enabled: !busy,
                  onTap: () => guarded(context, cubit.seedDemo),
                ),
                ListTile(
                  leading: const Icon(Icons.dataset_outlined),
                  title: const Text('Большой набор данных'),
                  subtitle: const Text(
                    '1 000 пользователей, 100 проектов, 10 000 задач',
                  ),
                  enabled: !busy,
                  onTap: () => guarded(context, cubit.seedLarge),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Очистить базу'),
                  subtitle: const Text('Удалить все данные приложения'),
                  enabled: !busy,
                  onTap: () async {
                    final yes = await confirm(
                      context,
                      title: 'Очистить базу?',
                      message: 'Все проекты, задачи и пользователи будут '
                          'удалены без возможности восстановления.',
                      action: 'Очистить',
                    );
                    if (!yes || !context.mounted) return;
                    await guarded(context, cubit.clearAll);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: const Text('Сравнить скорость запросов'),
                  subtitle: const Text(
                    'С индексами и без них, на отдельной временной базе',
                  ),
                  enabled: !busy,
                  onTap: () => guarded(context, cubit.runBenchmark),
                ),
                if (state.results.isNotEmpty) _Results(rows: state.results),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.rows});

  final List<BenchmarkRow> rows;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Среднее время запроса, мс'),
        ),
        for (final row in rows)
          ListTile(
            dense: true,
            title: Text(row.name),
            subtitle: Text(
              'С индексом: ${row.withIndexMs.toStringAsFixed(2)}  ·  '
              'без индекса: ${row.withoutIndexMs.toStringAsFixed(2)}\n'
              '${row.planWithIndex}',
              style: small,
            ),
            trailing: Text('×${row.speedup.toStringAsFixed(1)}'),
          ),
      ],
    );
  }
}
