import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/entities.dart';
import '../models/views.dart';
import '../repositories/task_repository.dart';
import '../state/feature_cubits.dart';
import '../state/tasks_cubit.dart';
import '../state/watch_cubit.dart';
import 'common.dart';
import 'tasks/task_list.dart';

Future<void> showUserForm(BuildContext context, {User? user}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _UserDialog(user: user),
  );
}

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UsersCubit, WatchState<List<User>>>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = state.data ?? const <User>[];
        if (users.isEmpty) {
          return const EmptyView(
            icon: Icons.people_outline,
            text: 'Пользователей пока нет',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return ListTile(
              leading: CircleAvatar(
                child: Text(user.name.characters.first.toUpperCase()),
              ),
              title: Text(user.name),
              subtitle: Text(
                '${user.email}\n'
                'Зарегистрирован ${formatDate(user.registeredAt)}',
              ),
              isThreeLine: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BlocProvider(
                    create: (context) => TasksCubit(
                      context.read<TaskRepository>(),
                      filter: TaskFilter(assigneeId: user.id),
                    ),
                    child: _UserDetailsScreen(user: user),
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

class _UserDetailsScreen extends StatelessWidget {
  const _UserDetailsScreen({required this.user});

  final User user;

  Future<void> _delete(BuildContext context) async {
    final cubit = context.read<UsersCubit>();
    final navigator = Navigator.of(context);
    final yes = await confirm(
      context,
      title: 'Удалить пользователя?',
      message: '${user.name} будет удалён из всех проектов.',
    );
    if (!yes || !context.mounted) return;
    final ok = await guarded(context, () => cubit.delete(user.id));
    if (ok) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UsersCubit, WatchState<List<User>>>(
      builder: (context, state) {
        final current = (state.data ?? const <User>[])
            .where((u) => u.id == user.id)
            .firstOrNull;
        return Scaffold(
          appBar: AppBar(
            title: Text(current?.name ?? user.name),
            actions: [
              IconButton(
                tooltip: 'Изменить',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    showUserForm(context, user: current ?? user),
              ),
              IconButton(
                tooltip: 'Удалить пользователя',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context),
              ),
            ],
          ),
          body: const TaskList(),
        );
      },
    );
  }
}

class _UserDialog extends StatefulWidget {
  const _UserDialog({this.user});

  final User? user;

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  late final _name = TextEditingController(text: widget.user?.name);
  late final _email = TextEditingController(text: widget.user?.email);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cubit = context.read<UsersCubit>();
    final navigator = Navigator.of(context);
    final user = widget.user;
    try {
      if (user == null) {
        await cubit.create(_name.text, _email.text);
      } else {
        await cubit.update(user.id, _name.text, _email.text);
      }
      navigator.pop();
    } on Exception catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.user == null ? 'Новый пользователь' : 'Изменить'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Email', errorText: _error),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }
}
