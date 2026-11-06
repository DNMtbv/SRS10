import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

class WatchState<T> {
  const WatchState({this.data, this.error});

  final T? data;
  final Object? error;

  bool get isLoading => data == null && error == null;
}

/// Подписывается на `watch()` из репозитория. Экран перестраивается сам, когда
/// данные в базе меняются.
class WatchCubit<T> extends Cubit<WatchState<T>> {
  WatchCubit(Stream<T> stream) : super(WatchState<T>()) {
    _subscription = stream.listen(
      (data) => emit(WatchState<T>(data: data)),
      onError: (Object error) =>
          emit(WatchState<T>(data: state.data, error: error)),
    );
  }

  late final StreamSubscription<T> _subscription;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
