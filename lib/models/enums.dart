/// Значения хранятся в SQLite как имя enum (`inProgress`, `critical` и т. д.).
enum TaskStatus {
  todo('Ожидает'),
  inProgress('Выполняется'),
  done('Завершена'),
  cancelled('Отменена');

  const TaskStatus(this.label);

  final String label;

  /// Незавершённая задача: над ней ещё предстоит работать.
  bool get isOpen => this == todo || this == inProgress;
}

enum TaskPriority {
  low('Низкий'),
  medium('Средний'),
  high('Высокий'),
  critical('Критический');

  const TaskPriority(this.label);

  final String label;
}

enum ProjectStatus {
  active('Активный'),
  completed('Завершённый'),
  archived('Архивный');

  const ProjectStatus(this.label);

  final String label;
}

enum ProjectRole {
  owner('Owner'),
  admin('Admin'),
  member('Member');

  const ProjectRole(this.label);

  final String label;
}

enum HistoryEvent {
  created('Задача создана'),
  statusChanged('Статус изменён'),
  statusUndone('Изменение статуса отменено'),
  reassigned('Сменился исполнитель');

  const HistoryEvent(this.label);

  final String label;
}

enum TaskSort {
  createdDesc('Сначала новые'),
  createdAsc('Сначала старые'),
  deadlineAsc('Дедлайн: ближайшие'),
  deadlineDesc('Дедлайн: дальние');

  const TaskSort(this.label);

  final String label;
}
