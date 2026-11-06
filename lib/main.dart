import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'database/app_database.dart';
import 'dependencies.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final database = AppDatabase(driftDatabase(name: 'taskflow'));
  final dependencies = Dependencies(
    database: database,
    attachmentsDirectory: () async {
      final documents = await getApplicationDocumentsDirectory();
      return Directory(p.join(documents.path, 'attachments'));
    },
    temporaryDirectory: getTemporaryDirectory,
  );

  runApp(TaskFlowApp(dependencies: dependencies));
}
