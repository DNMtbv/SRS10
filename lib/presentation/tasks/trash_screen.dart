import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/views.dart';
import '../../repositories/attachment_repository.dart';
import '../../repositories/task_repository.dart';
import '../../state/feature_cubits.dart';
import '../../state/watch_cubit.dart';
import '../common.dart';
import 'task_list.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TrashCubit(
        context.read<TaskRepository>(),
        context.read<AttachmentRepository>(),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('Корзина')),
        body: BlocBuilder<TrashCubit, WatchState<List<TaskView>>>(
          builder: (context, state) {
            final tasks = state.data ?? const <TaskView>[];
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (tasks.isEmpty) {
              return const EmptyView(
                icon: Icons.delete_outline,
                text: 'Корзина пуста',
              );
            }
            final cubit = context.read<TrashCubit>();
            return ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final view = tasks[index];
                return TaskTile(
                  view: view,
                  onTap: () {},
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Восстановить',
                        icon: const Icon(Icons.restore),
                        onPressed: () => guarded(
                          context,
                          () => cubit.restore(view.task.id),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Удалить навсегда',
                        icon: const Icon(Icons.delete_forever),
                        onPressed: () async {
                          final yes = await confirm(
                            context,
                            title: 'Удалить навсегда?',
                            message: 'Вместе с задачей удалятся комментарии, '
                                'вложения и история. Отменить это нельзя.',
                          );
                          if (!yes || !context.mounted) return;
                          await guarded(
                            context,
                            () => cubit.deletePermanently(view.task.id),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
