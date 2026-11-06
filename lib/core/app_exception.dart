/// Ошибка, текст которой можно показать пользователю.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Значение не прошло проверку перед сохранением.
class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// Запись не найдена.
class NotFoundException extends AppException {
  const NotFoundException(super.message);
}

/// Действие запрещено правилами приложения.
class RuleViolationException extends AppException {
  const RuleViolationException(super.message);
}

/// SQLite отклонил запись: сработал UNIQUE, FOREIGN KEY или CHECK.
class DataIntegrityException extends AppException {
  const DataIntegrityException(super.message);
}

/// Выполняет запрос и переводит ошибку ограничений SQLite в [AppException].
///
/// Сравнение по тексту нужно потому, что база работает в отдельном isolate:
/// ошибка приходит оттуда в обёртке, а не как `SqliteException`.
Future<T> guardDb<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on AppException {
    rethrow;
  } catch (e) {
    if (e.toString().contains('constraint failed')) {
      throw const DataIntegrityException(
        'Операция отменена: нарушена целостность данных',
      );
    }
    rethrow;
  }
}
