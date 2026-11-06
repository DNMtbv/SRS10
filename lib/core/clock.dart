/// Источник текущего времени. В тестах подменяется на фиксированную дату.
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();

/// Начало календарного дня: дедлайн хранится как дата, без времени.
DateTime startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);
