SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[F_WORKS_LIST2] ()
RETURNS @RESULT TABLE
(
    ID_WORK INT,
    CREATE_Date DATETIME,
    MaterialNumber DECIMAL(8,2),
    IS_Complit BIT,
    FIO VARCHAR(255),
    D_DATE varchar(10),
    WorkItemsNotComplit int,
    WorkItemsComplit int,
    FULL_NAME VARCHAR(101),
    StatusId smallint,
    StatusName VARCHAR(255),
    Is_Print bit
)
AS
BEGIN
    INSERT INTO @RESULT
    SELECT
        w.Id_Work,
        w.CREATE_Date,
        w.MaterialNumber,
        w.IS_Complit,
        w.FIO,
        CONVERT(VARCHAR(10), w.CREATE_Date, 104) AS D_DATE,
        ISNULL(wi_count.NotComplit, 0),
        ISNULL(wi_count.Complit, 0),
        ISNULL(emp.FULL_NAME, CAST(w.Id_Employee AS VARCHAR(101))),
        w.StatusId,
        ws.StatusName,
        CASE 
            WHEN w.Print_Date IS NOT NULL OR w.SendToClientDate IS NOT NULL 
              OR w.SendToDoctorDate IS NOT NULL OR w.SendToOrgDate IS NOT NULL OR w.SendToFax IS NOT NULL 
            THEN 1 ELSE 0 
        END AS Is_Print
    FROM Works w
    LEFT JOIN WorkStatus ws ON ws.StatusID = w.StatusId
    LEFT JOIN (
        SELECT 
            wi.Id_Work,
            COUNT(CASE WHEN wi.Is_Complit = 0 THEN 1 END) AS NotComplit,
            COUNT(CASE WHEN wi.Is_Complit = 1 THEN 1 END) AS Complit
        FROM WorkItem wi
        WHERE wi.ID_ANALIZ NOT IN (SELECT ID_ANALIZ FROM Analiz WHERE IS_GROUP = 1)
        GROUP BY wi.Id_Work
    ) wi_count ON wi_count.Id_Work = w.Id_Work
    LEFT JOIN (
        SELECT 
            Id_Employee,
            RTRIM(SURNAME + ' ' + 
                COALESCE(NULLIF(UPPER(LEFT(Name,1)),''), '') + '. ' + 
                COALESCE(NULLIF(UPPER(LEFT(Patronymic,1)),''), '') + '.') AS FULL_NAME
        FROM Employee
    ) emp ON emp.Id_Employee = w.Id_Employee
    WHERE w.Is_Del <> 1
    ORDER BY w.Id_Work DESC;

    RETURN;
END
GO
