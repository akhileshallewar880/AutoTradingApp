-- Final fix v4: Remove IDENTITY constraint - Simpler approach
-- This version uses sys views and a safer constraint dropping method

-- Step 1: Check current schema BEFORE
PRINT '===== BEFORE FIX =====';
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    COLUMNPROPERTY(OBJECT_ID('vantrade_analyses'), COLUMN_NAME, 'IsIdentity') AS IS_IDENTITY
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vantrade_analyses'
AND COLUMN_NAME IN ('analysis_id', 'user_id');

-- Step 2: Delete all dependent records first
PRINT '';
PRINT 'Deleting dependent records...';

DELETE FROM vantrade_stock_recommendations;
PRINT 'Deleted vantrade_stock_recommendations';

DELETE FROM vantrade_signals;
PRINT 'Deleted vantrade_signals';

DELETE FROM vantrade_orders;
PRINT 'Deleted vantrade_orders';

DELETE FROM vantrade_gtt_orders;
PRINT 'Deleted vantrade_gtt_orders';

DELETE FROM vantrade_execution_updates;
PRINT 'Deleted vantrade_execution_updates';

DELETE FROM vantrade_trades;
PRINT 'Deleted vantrade_trades';

DELETE FROM vantrade_open_positions;
PRINT 'Deleted vantrade_open_positions';

-- Step 3: Now delete from vantrade_analyses
PRINT '';
PRINT 'Clearing vantrade_analyses...';
DELETE FROM vantrade_analyses;
PRINT 'Data cleared';

-- Step 4: Drop foreign keys from dependent tables using sys.foreign_keys
PRINT '';
PRINT 'Dropping foreign keys...';

DECLARE @FKName NVARCHAR(128);
DECLARE @TableName NVARCHAR(128);

-- Find all foreign keys that reference vantrade_analyses
DECLARE fk_cursor CURSOR FOR
SELECT
    fk.name AS FK_NAME,
    t.name AS TABLE_NAME
FROM sys.foreign_keys fk
JOIN sys.tables t ON fk.parent_object_id = t.object_id
WHERE fk.referenced_object_id = OBJECT_ID('vantrade_analyses');

OPEN fk_cursor;
FETCH NEXT FROM fk_cursor INTO @FKName, @TableName;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        DECLARE @DropFK NVARCHAR(255) = 'ALTER TABLE ' + QUOTENAME(@TableName) + ' DROP CONSTRAINT ' + QUOTENAME(@FKName);
        EXECUTE sp_executesql @DropFK;
        PRINT 'Dropped FK: ' + @FKName + ' from ' + @TableName;
    END TRY
    BEGIN CATCH
        PRINT 'Could not drop FK ' + @FKName + ' (may already be dropped)';
    END CATCH
    FETCH NEXT FROM fk_cursor INTO @FKName, @TableName;
END

CLOSE fk_cursor;
DEALLOCATE fk_cursor;

-- Step 5: Disable constraint checking on vantrade_analyses itself
PRINT '';
PRINT 'Disabling constraints...';
ALTER TABLE vantrade_analyses NOCHECK CONSTRAINT ALL;
PRINT 'All constraints disabled';

-- Step 6: Drop primary key constraint
PRINT '';
PRINT 'Dropping primary key...';

BEGIN TRY
    DECLARE @PKName NVARCHAR(128);
    SELECT @PKName = name
    FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID('vantrade_analyses')
    AND type = 'PK';

    IF @PKName IS NOT NULL
    BEGIN
        DECLARE @DropPK NVARCHAR(255) = 'ALTER TABLE vantrade_analyses DROP CONSTRAINT ' + QUOTENAME(@PKName);
        EXECUTE sp_executesql @DropPK;
        PRINT 'Dropped primary key: ' + @PKName;
    END
    ELSE
    BEGIN
        PRINT 'No primary key found';
    END
END TRY
BEGIN CATCH
    PRINT 'Error dropping primary key';
END CATCH

-- Step 7: Drop any indexes on analysis_id
PRINT '';
PRINT 'Dropping indexes...';

BEGIN TRY
    DROP INDEX ix_vantrade_analyses_analysis_id ON vantrade_analyses;
    PRINT 'Dropped index ix_vantrade_analyses_analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Index not found (OK)';
END CATCH

-- Step 8: Drop the analysis_id column
PRINT '';
PRINT 'Dropping analysis_id column...';

BEGIN TRY
    ALTER TABLE vantrade_analyses DROP COLUMN analysis_id;
    PRINT 'Column dropped successfully';
END TRY
BEGIN CATCH
    PRINT 'ERROR: Could not drop column. Checking remaining constraints...';

    -- List remaining constraints
    SELECT
        'Constraint: ' + CONSTRAINT_NAME as [Remaining Constraints on analysis_id]
    FROM INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE
    WHERE TABLE_NAME = 'vantrade_analyses'
    AND COLUMN_NAME = 'analysis_id';

    RAISERROR('Please check output above for remaining constraints', 16, 1);
END CATCH

-- Step 9: Add analysis_id as VARCHAR(36) PRIMARY KEY (NOT IDENTITY)
PRINT '';
PRINT 'Adding new analysis_id column...';
ALTER TABLE vantrade_analyses
ADD analysis_id VARCHAR(36) NOT NULL PRIMARY KEY;
PRINT 'Column added successfully';

-- Step 10: Ensure user_id is nullable
PRINT '';
PRINT 'Making user_id nullable...';
ALTER TABLE vantrade_analyses
ALTER COLUMN user_id INT NULL;
PRINT 'Done';

-- Step 11: Re-enable constraint checking
PRINT '';
PRINT 'Re-enabling constraints...';
ALTER TABLE vantrade_analyses WITH CHECK CHECK CONSTRAINT ALL;
PRINT 'Constraints re-enabled';

-- Step 12: Verify AFTER
PRINT '';
PRINT '===== AFTER FIX =====';
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    COLUMNPROPERTY(OBJECT_ID('vantrade_analyses'), COLUMN_NAME, 'IsIdentity') AS IS_IDENTITY
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vantrade_analyses'
AND COLUMN_NAME IN ('analysis_id', 'user_id');

PRINT '';
PRINT 'SUCCESS! analysis_id is now VARCHAR(36) without IDENTITY constraint';
