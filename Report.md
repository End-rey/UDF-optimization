
# Отчёт по оптимизации функции `F_WORKS_LIST`

## Задача 1 уровня: Анализ текущей реализации

Функция `dbo.F_WORKS_LIST()` возвращает список заказов с информацией по количеству выполненных и невыполненных элементов, статусами и ФИО сотрудников. Основные проблемы производительности:

| Проблема | Описание |
|---------|----------|
| Скалярные функции в SELECT | `F_EMPLOYEE_FULLNAME` и `F_WORKITEMS_COUNT_BY_ID_WORK` вызываются по строкам, что ведёт к множественным обращениям к таблицам. |
| Повторный вызов одной функции | `F_WORKITEMS_COUNT_BY_ID_WORK` вызывается дважды — для выполненных и невыполненных. |
| Неинлайновая табличная функция | Используется `RETURN @RESULT`, что препятствует оптимизациям. |
| Джойны выполняются до фильтрации | Фильтрация `Is_Del <> 1` происходит после джойнов. |
| Отсутствие индекса | Нет индекса по `Is_Del, Id_Work DESC` для ускорения `ORDER BY`. |

Время выполнения функции:
```
SQL Server Execution Times:
   CPU time = 5072 ms,  elapsed time = 5366 ms.
```

---

## Задача 2 уровня: Предложенные оптимизации

Цель: снизить время выполнения `SELECT TOP 3000 * FROM dbo.F_WORKS_LIST()` до менее, чем 1–2 секунд без изменения структуры БД.

### Основные шаги:

- Заменены вызовы UDF `F_WORKITEMS_COUNT_BY_ID_WORK` на агрегатный `LEFT JOIN` с `GROUP BY`.
- Логика `F_EMPLOYEE_FULLNAME` реализована через `JOIN` к `Employee` с построением ФИО.
- Добавлен явный `LEFT JOIN` к `WorkStatus`.
- Предложен индекс:

```sql
CREATE NONCLUSTERED INDEX IX_Works_IsDel_IdWork ON Works (Is_Del, Id_Work DESC);
```

### Результат

Создана оптимизированная функция:

```sql
SELECT TOP 3000 * FROM dbo.F_WORKS_LIST2()
```

Выполняется значительно быстрее при том же выводе:
```
SQL Server Execution Times:
   CPU time = 187 ms,  elapsed time = 190 ms.
```

---

## Задача 3 уровня: Возможные структурные улучшения

### Предложенные изменения в структуре БД

#### 1. Создание предрасчитанной таблицы `WorkStats`
Создаётся отдельная таблица, где будут храниться заранее рассчитанные агрегаты по каждому заказу (`Id_Work`).

```sql
CREATE TABLE dbo.WorkStats (
    Id_Work INT PRIMARY KEY,
    WorkItemsNotComplit INT NOT NULL,
    WorkItemsComplit INT NOT NULL,
    EmployeeFullName VARCHAR(101) NOT NULL
);
```

#### 2. Автоматическое обновление агрегатов через триггеры

```sql
CREATE TRIGGER trg_Update_WorkStats
ON WorkItem
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.WorkStats AS target
    USING (
        SELECT 
            wi.Id_Work,
            COUNT(CASE WHEN wi.Is_Complit = 0 THEN 1 END) AS NotComplit,
            COUNT(CASE WHEN wi.Is_Complit = 1 THEN 1 END) AS Complit,
            MAX(e.Surname + ' ' + UPPER(LEFT(e.Name, 1)) + '. ' + UPPER(LEFT(e.Patronymic, 1)) + '.') AS FullName
        FROM WorkItem wi
        JOIN Works w ON w.Id_Work = wi.Id_Work
        JOIN Employee e ON e.Id_Employee = w.Id_Employee
        WHERE wi.Id_Work IN (
            SELECT DISTINCT Id_Work FROM inserted
            UNION
            SELECT DISTINCT Id_Work FROM deleted
        )
        GROUP BY wi.Id_Work
    ) AS source
    ON target.Id_Work = source.Id_Work
    WHEN MATCHED THEN
        UPDATE SET 
            WorkItemsNotComplit = source.NotComplit,
            WorkItemsComplit = source.Complit,
            EmployeeFullName = source.FullName
    WHEN NOT MATCHED THEN
        INSERT (Id_Work, WorkItemsNotComplit, WorkItemsComplit, EmployeeFullName)
        VALUES (source.Id_Work, source.NotComplit, source.Complit, source.FullName);
END;
```

#### 3. Изменение F_WORKS_LIST
В функции `F_WORKS_LIST` необходимо заменить вызовы функций `F_EMPLOYEE_FULLNAME` и `F_WORKITEMS_COUNT_BY_ID_WORK` на `JOIN WorkStats` по `Id_Work`.

#### 4. Добавление индексов

```sql
CREATE NONCLUSTERED INDEX IX_Works_FastSelect ON Works (Is_Del, Id_Work DESC, Id_Employee, StatusId);
CREATE NONCLUSTERED INDEX IX_WorkItem_IdWork_Analiz ON WorkItem (Id_Work, Is_Complit, ID_ANALIZ);
```

### Возможные недостатки и отрицательные последствия

1. **Увеличение объёма базы данных.**
   - Добавление новой таблицы и индексов приводит к дополнительному использованию дискового пространства.

2. **Сложность поддержки согласованности данных.**
   - Необходимость обеспечить полную синхронность таблицы `WorkStats` с изменениями в `WorkItem`, `Employee` и `Works`. Любые ошибки в триггерах или логике обновления могут привести к рассинхронизации.

3. **Ухудшение производительности операций записи.**
   - При использовании триггеров каждое изменение в `WorkItem` (вставка, обновление, удаление) приводит к дополнительным операциям обновления в `WorkStats`, что увеличивает нагрузку на транзакции.

4. **Сложность тестирования и отладки.**
   - Поведение системы становится менее предсказуемым, так как данные из `WorkStats` могут не соответствовать актуальному состоянию других таблиц, особенно в случае ошибок или отменённых транзакций.

5. **Невозможность откатить изменения без потери данных.**
   - Удаление `WorkStats` приведёт к потере всех агрегированных данных, если они не пересчитываются регулярно.

6. **Сложности миграции.**
   - При изменении логики расчёта агрегатов потребуется изменение триггера и возможное пересоздание содержимого `WorkStats`.

### Вывод
Оптимизация функции `F_WORKS_LIST` через создание агрегированной таблицы `WorkStats` и добавление индексов позволяет значительно ускорить выполнение запроса. Однако это влечёт за собой дополнительные требования к поддержке согласованности данных и может повлиять на производительность операций записи. Подход следует использовать только при уверенности в необходимости такого рода оптимизации.

## Использованный LLM промпт

### Генерация тестовых данных
```
Мне необходимо сгенерировать тестовые данные для MS SQL Server. Структура базы включает таблицы Works, WorkItem, Employee, Analiz, WorkStatus. Нужно создать 100 сотрудников, 200 анализов, 5 статусов, 50000 заказов и в среднем по 3 WorkItem на заказ (примерно 150000 элементов). Данные должны вставляться быстро. Используй надёжный способ генерации чисел.
```

### Оптимизация функции F_WORKS_LIST без изменения структуры
```
Предложи оптимизированный вариант SQL-запроса, аналогичного функции F_WORKS_LIST. Не изменяй структуру таблиц. Цель — ускорить выполнение запроса до 1–2 секунд при объёме 50000 заказов и 150000 WorkItem.
```

---

**Итог:** Предложенные правки позволяют достичь необходимой производительности без изменения структуры базы. Дополнительная оптимизация возможна при изменении архитектуры.
