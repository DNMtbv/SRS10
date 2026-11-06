import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/app_exception.dart';
import '../models/entities.dart';
import '../models/enums.dart';
import '../state/session_cubit.dart';

String formatDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

String formatDateTime(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${formatDate(d)} ${two(d.hour)}:${two(d.minute)}';
}

/// Выполняет действие и показывает понятную ошибку. Возвращает true при успехе.
Future<bool> guarded(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    return true;
  } on AppException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Автор действия. Если пользователь не выбран, показывает подсказку.
int? actorOf(BuildContext context) {
  try {
    return context.read<SessionCubit>().requireUserId();
  } on AppException catch (e) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message)));
    return null;
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Удалить',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

class EmptyView extends StatelessWidget {
  const EmptyView({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag({required this.text, required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

Color statusColor(TaskStatus status) => switch (status) {
      TaskStatus.todo => Colors.blueGrey.shade700,
      TaskStatus.inProgress => Colors.blue.shade800,
      TaskStatus.done => Colors.green.shade800,
      TaskStatus.cancelled => Colors.grey.shade700,
    };

Color priorityColor(TaskPriority priority) => switch (priority) {
      TaskPriority.low => Colors.teal.shade700,
      TaskPriority.medium => Colors.indigo.shade600,
      TaskPriority.high => Colors.orange.shade900,
      TaskPriority.critical => Colors.red.shade800,
    };

/// Выбор пользователя с поиском: список может содержать тысячу строк.
Future<User?> pickUser(
  BuildContext context, {
  required List<User> users,
  required String title,
}) {
  return showModalBottomSheet<User>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _UserPicker(users: users, title: title),
  );
}

class _UserPicker extends StatefulWidget {
  const _UserPicker({required this.users, required this.title});

  final List<User> users;
  final String title;

  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final users = widget.users
        .where(
          (u) =>
              u.name.toLowerCase().contains(query) ||
              u.email.contains(query),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Имя или email',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: users.isEmpty
                  ? const EmptyView(
                      icon: Icons.person_off_outlined,
                      text: 'Никого не найдено',
                    )
                  : ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return ListTile(
                          title: Text(user.name),
                          subtitle: Text(user.email),
                          onTap: () => Navigator.pop(context, user),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
