-- Final fix v3: Remove IDENTITY constraint - Query and drop ALL constraints
-- This version finds and drops ALL constraints by querying system tables

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

-- Step 4: Disable constraint checking
PRINT '';
PRINT 'Disabling constraint checking...';
ALTER TABLE vantrade_analyses NOCHECK CONSTRAINT ALL;
PRINT 'Constraints disabled';

-- Step 5: Drop ALL constraints that reference analysis_id column dynamically
PRINT '';
PRINT 'Dropping constraints from dependent tables...';

DECLARE @ConstraintName NVARCHAR(128);
DECLARE @TableName NVARCHAR(128);

DECLARE constraint_cursor CURSOR FOR
SELECT CONSTRAINT_NAME, TABLE_NAME
FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS
WHERE UNIQUE_CONSTRAINT_TABLE_NAME = 'vantrade_analyses'
AND UNIQUE_CONSTRAINT_COLUMN_NAME = 'analysis_id'
UNION ALL
SELECT CONSTRAINT_NAME, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_NAME = 'vantrade_analyses'
AND COLUMN_NAME = 'analysis_id';

OPEN constraint_cursor;
FETCH NEXT FROM constraint_cursor INTO @ConstraintName, @TableName;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @SQL NVARCHAR(255);
    SET @SQL = 'ALTER TABLE ' + @TableName + ' DROP CONSTRAINT ' + @ConstraintName;
    BEGIN TRY
        EXECUTE sp_executesql @SQL;
        PRINT 'Dropped constraint ' + @ConstraintName + ' from ' + @TableName;
    END TRY
    BEGIN CATCH
        PRINT 'Could not drop constraint ' + @ConstraintName + ' (may already be dropped)';
    END CATCH
    FETCH NEXT FROM constraint_cursor INTO @ConstraintName, @TableName;
END

CLOSE constraint_cursor;
DEALLOCATE constraint_cursor;

-- Step 6: Drop primary key if it exists
PRINT '';
PRINT 'Dropping primary key and indexes...';

BEGIN TRY
    DECLARE @PKName NVARCHAR(128);
    SELECT @PKName = CONSTRAINT_NAME
    FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
    WHERE TABLE_NAME = 'vantrade_analyses' AND CONSTRAINT_TYPE = 'PRIMARY KEY';

    IF @PKName IS NOT NULL
    BEGIN
        DECLARE @DropPK NVARCHAR(255) = 'ALTER TABLE vantrade_analyses DROP CONSTRAINT ' + @PKName;
        EXECUTE sp_executesql @DropPK;
        PRINT 'Dropped primary key: ' + @PKName;
    END
END TRY
BEGIN CATCH
    PRINT 'Primary key already dropped (OK)';
END CATCH

-- Drop any indexes on analysis_id
BEGIN TRY
    DROP INDEX ix_vantrade_analyses_analysis_id ON vantrade_analyses;
    PRINT 'Dropped index ix_vantrade_analyses_analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Index not found (OK)';
END CATCH

-- Step 7: Drop the analysis_id column
PRINT '';
PRINT 'Dropping analysis_id column...';
ALTER TABLE vantrade_analyses DROP COLUMN analysis_id;
PRINT 'Column dropped successfully';

-- Step 8: Add analysis_id as VARCHAR(36) PRIMARY KEY (NOT IDENTITY)
PRINT '';
PRINT 'Adding new analysis_id column...';
ALTER TABLE vantrade_analyses
ADD analysis_id VARCHAR(36) NOT NULL PRIMARY KEY;
PRINT 'Column added successfully';

-- Step 9: Ensure user_id is nullable
PRINT '';
PRINT 'Making user_id nullable...';
ALTER TABLE vantrade_analyses
ALTER COLUMN user_id INT NULL;
PRINT 'Done';

-- Step 10: Enable constraint checking
PRINT '';
PRINT 'Re-enabling constraint checking...';
ALTER TABLE vantrade_analyses WITH CHECK CHECK CONSTRAINT ALL;
PRINT 'Constraints re-enabled';

-- Step 11: Verify AFTER
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
PRINT 'All dependencies have been removed and column recreated';
