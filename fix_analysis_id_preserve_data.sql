-- Fix analysis_id IDENTITY constraint - PRESERVE DATA VERSION
-- This approach backs up existing data before recreating the column

-- Step 1: Check if there's existing data
SELECT COUNT(*) as existing_analyses FROM vantrade_analyses;

-- Step 2: Backup existing analysis_id values to a temp table
SELECT
    CAST(analysis_id AS VARCHAR(36)) as old_id,
    user_id,
    status,
    hold_duration_days,
    total_investment,
    max_profit,
    max_loss,
    created_at,
    completed_at
INTO #temp_analyses_backup
FROM vantrade_analyses;

-- Step 3: Drop dependent constraints
BEGIN TRY
    ALTER TABLE vantrade_analyses
    DROP CONSTRAINT FK_vantrade_analyses_user_id;
END TRY
BEGIN CATCH
    PRINT 'Foreign key not found';
END CATCH

-- Step 4: Drop primary key
BEGIN TRY
    ALTER TABLE vantrade_analyses
    DROP CONSTRAINT PK_vantrade_analyses;
END TRY
BEGIN CATCH
    PRINT 'Primary key not found';
END CATCH

-- Step 5: Drop the identity column
ALTER TABLE vantrade_analyses
DROP COLUMN analysis_id;

-- Step 6: Add new analysis_id column as VARCHAR(36) with PRIMARY KEY
ALTER TABLE vantrade_analyses
ADD analysis_id VARCHAR(36) NOT NULL PRIMARY KEY;

-- Step 7: Make user_id nullable
ALTER TABLE vantrade_analyses
ALTER COLUMN user_id INT NULL;

-- Step 8: Restore data from backup
UPDATE vantrade_analyses
SET analysis_id = temp.old_id
FROM vantrade_analyses va
INNER JOIN #temp_analyses_backup temp ON va.user_id = temp.user_id
WHERE va.created_at = temp.created_at;

-- Step 9: Recreate foreign key
BEGIN TRY
    ALTER TABLE vantrade_analyses
    ADD CONSTRAINT FK_vantrade_analyses_user_id
    FOREIGN KEY (user_id) REFERENCES vantrade_users(user_id)
    ON DELETE SET NULL;
END TRY
BEGIN CATCH
    PRINT 'Could not recreate foreign key';
END CATCH

-- Step 10: Clean up temp table
DROP TABLE #temp_analyses_backup;

-- Step 11: Verify final schema
PRINT '';
PRINT '===== FINAL SCHEMA =====';
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    COLUMNPROPERTY(OBJECT_ID('vantrade_analyses'), COLUMN_NAME, 'IsIdentity') AS IS_IDENTITY
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vantrade_analyses'
AND COLUMN_NAME IN ('analysis_id', 'user_id');

PRINT '';
PRINT '===== DATA COUNT =====';
SELECT COUNT(*) as restored_analyses FROM vantrade_analyses;
