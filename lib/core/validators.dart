import 'app_exception.dart';

/// Проверки перед сохранением. Вызываются в репозиториях, поэтому работают
/// и для формы, и для любого другого источника данных.
abstract final class Validators {
  static final _email = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  static String name(String value) {
    final v = value.trim();
    if (v.length < 2) throw const ValidationException('Имя: минимум 2 символа');
    if (v.length > 100) {
      throw const ValidationException('Имя: максимум 100 символов');
    }
    return v;
  }

  /// Email без учёта регистра: `A@mail.kz` и `a@mail.kz` — один адрес.
  static String email(String value) {
    final v = value.trim().toLowerCase();
    if (!_email.hasMatch(v)) {
      throw const ValidationException('Некорректный email');
    }
    return v;
  }

  static String title(String value, {String field = 'Название'}) {
    final v = value.trim();
    if (v.isEmpty) throw ValidationException('$field обязательно');
    if (v.length > 200) {
      throw ValidationException('$field: максимум 200 символов');
    }
    return v;
  }

  static String comment(String value) {
    final v = value.trim();
    if (v.isEmpty) throw const ValidationException('Комментарий пустой');
    if (v.length > 2000) {
      throw const ValidationException('Комментарий: максимум 2000 символов');
    }
    return v;
  }
}
