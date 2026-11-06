import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/entities.dart';
import '../repositories/task_repository.dart';
import '../state/feature_cubits.dart';
import '../state/session_cubit.dart';
import '../state/tasks_cubit.dart';
import 'common.dart';
import 'dashboard_screen.dart';
import 'projects_screen.dart';
import 'tasks/task_form_screen.dart';
import 'tasks/task_list.dart';
import 'tasks/trash_screen.dart';
import 'tools_screen.dart';
import 'users_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _titles = ['Проекты', 'Задачи', 'Пользователи', 'Статистика'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Корзина',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const TrashScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Инструменты',
            icon: const Icon(Icons.build_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ToolsScreen()),
            ),
          ),
          const _CurrentUserButton(),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          const ProjectsScreen(),
          BlocProvider(
            create: (context) => TasksCubit(context.read<TaskRepository>()),
            child: const TaskList(),
          ),
          const UsersScreen(),
          const DashboardScreen(),
        ],
      ),
      floatingActionButton: switch (_tab) {
        0 => FloatingActionButton.extended(
            heroTag: 'project',
            icon: const Icon(Icons.add),
            label: const Text('Проект'),
            onPressed: () => openProjectForm(context),
          ),
        1 => FloatingActionButton.extended(
            heroTag: 'task',
            icon: const Icon(Icons.add),
            label: const Text('Задача'),
            onPressed: () => openTaskForm(context),
          ),
        2 => FloatingActionButton.extended(
            heroTag: 'user',
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Пользователь'),
            onPressed: () => showUserForm(context),
          ),
        _ => null,
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            label: 'Проекты',
          ),
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Задачи'),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Люди',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart),
            label: 'Статистика',
          ),
        ],
      ),
    );
  }
}

class _CurrentUserButton extends StatelessWidget {
  const _CurrentUserButton();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, User?>(
      builder: (context, user) {
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: user == null
                ? 'Выбрать пользователя'
                : 'Текущий пользователь: ${user.name}',
            icon: CircleAvatar(
              radius: 15,
              child: user == null
                  ? const Icon(Icons.person_outline, size: 18)
                  : Text(user.name.characters.first.toUpperCase()),
            ),
            onPressed: () async {
              final session = context.read<SessionCubit>();
              final users = context.read<UsersCubit>().state.data ?? const [];
              final picked = await pickUser(
                context,
                users: users,
                title: 'Кто работает с приложением?',
              );
              if (picked != null) await session.select(picked.id);
            },
          ),
        );
      },
    );
  }
}
