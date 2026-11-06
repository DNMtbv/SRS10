import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/app_exception.dart';
import '../models/entities.dart';
import '../repositories/user_repository.dart';

/// Текущий пользователь: от его имени меняются статусы и пишутся комментарии.
/// Выбор хранится в SQLite, а если пользователя удалили, состояние станет null.
class SessionCubit extends Cubit<User?> {
  SessionCubit(this._users) : super(null) {
    _idSubscription = _users.watchCurrentUserId().listen(_follow);
  }

  final UserRepository _users;
  late final StreamSubscription<int?> _idSubscription;
  StreamSubscription<User?>? _userSubscription;

  /// `watch()` никогда не завершается, поэтому при смене выбора прошлую
  /// подписку нужно отменять самим. По той же причине здесь не подходит
  /// `asyncExpand`: он ждал бы конца потока и не увидел новый выбор.
  void _follow(int? id) {
    _userSubscription?.cancel();
    _userSubscription = null;
    if (id == null) {
      emit(null);
      return;
    }
    _userSubscription = _users.watchUser(id).listen(emit);
  }

  Future<void> select(int userId) => _users.setCurrentUser(userId);

  /// Для действий, которым нужен автор.
  int requireUserId() {
    final user = state;
    if (user == null) {
      throw const RuleViolationException('Сначала выберите текущего пользователя');
    }
    return user.id;
  }

  @override
  Future<void> close() async {
    await _idSubscription.cancel();
    await _userSubscription?.cancel();
    return super.close();
  }
}
