import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dependencies.dart';
import 'presentation/home_shell.dart';
import 'state/feature_cubits.dart';
import 'state/session_cubit.dart';

class TaskFlowApp extends StatelessWidget {
  const TaskFlowApp({required this.dependencies, super.key});

  final Dependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final d = dependencies;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: d.users),
        RepositoryProvider.value(value: d.projects),
        RepositoryProvider.value(value: d.tasks),
        RepositoryProvider.value(value: d.comments),
        RepositoryProvider.value(value: d.attachments),
        RepositoryProvider.value(value: d.stats),
        RepositoryProvider.value(value: d.maintenance),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => SessionCubit(d.users)),
          BlocProvider(create: (_) => UsersCubit(d.users)),
          BlocProvider(create: (_) => ProjectsCubit(d.projects, d.attachments)),
        ],
        child: MaterialApp(
          title: 'TaskFlow',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF00796B),
            useMaterial3: true,
          ),
          home: const HomeShell(),
        ),
      ),
    );
  }
}
