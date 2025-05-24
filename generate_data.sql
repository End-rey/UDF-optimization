DELETE FROM WorkItem;
DELETE FROM Works;
DELETE FROM Analiz;
DELETE FROM Employee;
DELETE FROM WorkStatus;

DBCC CHECKIDENT ('WorkItem', RESEED, 0);
DBCC CHECKIDENT ('Works', RESEED, 0);
DBCC CHECKIDENT ('Analiz', RESEED, 0);
DBCC CHECKIDENT ('Employee', RESEED, 0);
DBCC CHECKIDENT ('WorkStatus', RESEED, 0);

INSERT INTO Employee (Login_Name, Name, Patronymic, Surname, Email, Post, CreateDate, Archived, IS_Role)
SELECT 
  'user' + CAST(v.number AS VARCHAR), 
  'Имя' + CAST(v.number AS VARCHAR), 
  'О.' + CAST(v.number AS VARCHAR), 
  'Фамилия' + CAST(v.number AS VARCHAR), 
  'user' + CAST(v.number AS VARCHAR) + '@example.com',
  'Врач', 
  GETDATE(), 
  0, 
  0
FROM master.dbo.spt_values v
WHERE v.type = 'P' AND v.number BETWEEN 1 AND 100;

INSERT INTO Analiz (IS_GROUP, MATERIAL_TYPE, CODE_NAME, FULL_NAME, Text_Norm, Price)
SELECT 
  0,
  1,
  'A' + CAST(v.number AS VARCHAR),
  'Анализ ' + CAST(v.number AS VARCHAR),
  'норма',
  ROUND(RAND(CHECKSUM(NEWID())) * 1000, 2)
FROM master.dbo.spt_values v
WHERE v.type = 'P' AND v.number BETWEEN 1 AND 200;

INSERT INTO WorkStatus (StatusName)
VALUES ('Создан'), ('В процессе'), ('Готово'), ('Отправлено'), ('Удалено');

WITH Tally AS (
    SELECT TOP (50000)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM master.dbo.spt_values a
    CROSS JOIN master.dbo.spt_values b
),
Emp AS (
    SELECT ROW_NUMBER() OVER (ORDER BY Id_Employee) AS rn, Id_Employee FROM Employee
),
Stat AS (
    SELECT ROW_NUMBER() OVER (ORDER BY StatusID) AS rn, StatusID FROM WorkStatus
)
INSERT INTO Works (IS_Complit, CREATE_Date, Id_Employee, FIO, StatusId)
SELECT 
  CASE WHEN n % 2 = 0 THEN 1 ELSE 0 END,
  DATEADD(DAY, -n % 365, GETDATE()),
  e.Id_Employee,
  'Пациент ' + CAST(n AS VARCHAR),
  s.StatusID
FROM Tally t
JOIN Emp e ON e.rn = 1 + (t.n % (SELECT COUNT(*) FROM Emp))
JOIN Stat s ON s.rn = 1 + (t.n % (SELECT COUNT(*) FROM Stat));

WITH Anal AS (
    SELECT ROW_NUMBER() OVER (ORDER BY ID_ANALIZ) AS rn, ID_ANALIZ FROM Analiz
),
Emp AS (
    SELECT ROW_NUMBER() OVER (ORDER BY Id_Employee) AS rn, Id_Employee FROM Employee
),
Tally AS (
    SELECT TOP (150000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM master.dbo.spt_values a
    CROSS JOIN master.dbo.spt_values b
)
INSERT INTO WorkItem (Is_Complit, ID_ANALIZ, Id_Work, Id_Employee, Is_Print)
SELECT 
  CASE WHEN t.n % 2 = 0 THEN 1 ELSE 0 END,
  a.ID_ANALIZ,
  w.Id_Work,
  e.Id_Employee,
  1
FROM Tally t
JOIN Works w ON w.Id_Work = 1 + (t.n % 50000)
JOIN Anal a ON a.rn = 1 + (t.n % (SELECT COUNT(*) FROM Anal))
JOIN Emp e ON e.rn = 1 + (t.n % (SELECT COUNT(*) FROM Emp));

