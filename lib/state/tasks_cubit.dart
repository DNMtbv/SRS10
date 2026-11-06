import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/enums.dart';
import '../models/views.dart';
import '../repositories/task_repository.dart';

class TasksState extends Equatable {
  const TasksState({
    required this.filter,
    this.items = const [],
    this.limit = TasksCubit.pageSize,
    this.hasMore = false,
    this.isLoading = true,
    this.error,
  });

  final TaskFilter filter;
  final List<TaskView> items;
  final int limit;
  final bool hasMore;
  final bool isLoading;
  final String? error;

  TasksState copyWith({
    TaskFilter? filter,
    List<TaskView>? items,
    int? limit,
    bool? hasMore,
    bool? isLoading,
    String? error,
  }) {
    return TasksState(
      filter: filter ?? this.filter,
      items: items ?? this.items,
      limit: limit ?? this.limit,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  @override
  List<Object?> get props => [filter, items, limit, hasMore, isLoading, error];
}

/// Список задач с фильтрами и постраничной загрузкой. Подписка `watch()` живёт
/// на всём загруженном окне, поэтому список обновляется при любом изменении.
class TasksCubit extends Cubit<TasksState> {
  TasksCubit(
    this._tasks, {
    TaskFilter filter = const TaskFilter(),
    this._searchDelay = const Duration(milliseconds: 300),
  }) : super(TasksState(filter: filter)) {
    _subscribe();
  }

  static const pageSize = 20;

  final TaskRepository _tasks;
  final Duration _searchDelay;
  StreamSubscription<List<TaskView>>? _subscription;
  Timer? _debounce;

  /// Запрашивается на строку больше страницы: лишняя строка значит, что
  /// дальше есть ещё данные. Отдельный COUNT не нужен.
  void _subscribe() {
    _subscription?.cancel();
    final limit = state.limit;
    _subscription = _tasks.watchTasks(state.filter, limit: limit + 1).listen(
      (rows) {
        emit(
          state.copyWith(
            items: rows.take(limit).toList(),
            hasMore: rows.length > limit,
            isLoading: false,
          ),
        );
      },
      onError: (Object error) {
        emit(state.copyWith(isLoading: false, error: '$error'));
      },
    );
  }

  void loadMore() {
    if (!state.hasMore || state.isLoading) return;
    emit(state.copyWith(limit: state.limit + pageSize, isLoading: true));
    _subscribe();
  }

  void _apply(TaskFilter filter) {
    if (filter == state.filter) return;
    emit(state.copyWith(filter: filter, limit: pageSize, isLoading: true));
    _subscribe();
  }

  void setStatus(TaskStatus? value) =>
      _apply(state.filter.copyWith(status: () => value));

  void setPriority(TaskPriority? value) =>
      _apply(state.filter.copyWith(priority: () => value));

  void setAssignee(int? value) =>
      _apply(state.filter.copyWith(assigneeId: () => value));

  void setSort(TaskSort value) => _apply(state.filter.copyWith(sort: value));

  /// Запрос уходит после паузы в наборе, а не на каждую букву.
  void setQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDelay, () {
      _apply(state.filter.copyWith(query: value));
    });
  }

  @override
  Future<void> close() async {
    _debounce?.cancel();
    await _subscription?.cancel();
    return super.close();
  }
}
