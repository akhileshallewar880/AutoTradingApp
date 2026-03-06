-- Final fix: Remove IDENTITY constraint from existing analysis_id column
-- This handles the case where column already exists but has wrong properties

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

-- Step 2: Drop constraints
PRINT '';
PRINT 'Dropping constraints...';

BEGIN TRY
    ALTER TABLE vantrade_analyses DROP CONSTRAINT PK_vantrade_analyses;
    PRINT 'Primary key dropped';
END TRY
BEGIN CATCH
    PRINT 'Primary key not found (OK)';
END CATCH

BEGIN TRY
    ALTER TABLE vantrade_analyses DROP CONSTRAINT FK_vantrade_analyses_user_id;
    PRINT 'Foreign key dropped';
END TRY
BEGIN CATCH
    PRINT 'Foreign key not found (OK)';
END CATCH

-- Step 3: Delete all rows (to allow column recreation)
PRINT '';
PRINT 'Clearing table data...';
DELETE FROM vantrade_analyses;
PRINT 'Data cleared';

-- Step 4: Drop the analysis_id column
PRINT '';
PRINT 'Dropping analysis_id column...';
ALTER TABLE vantrade_analyses DROP COLUMN analysis_id;
PRINT 'Column dropped';

-- Step 5: Add analysis_id as VARCHAR(36) PRIMARY KEY (NOT IDENTITY)
PRINT '';
PRINT 'Adding new analysis_id column...';
ALTER TABLE vantrade_analyses
ADD analysis_id VARCHAR(36) NOT NULL PRIMARY KEY;
PRINT 'Column added successfully';

-- Step 6: Ensure user_id is nullable
PRINT '';
PRINT 'Making user_id nullable...';
ALTER TABLE vantrade_analyses
ALTER COLUMN user_id INT NULL;
PRINT 'Done';

-- Step 7: Recreate foreign key
PRINT '';
PRINT 'Recreating foreign key...';
BEGIN TRY
    ALTER TABLE vantrade_analyses
    ADD CONSTRAINT FK_vantrade_analyses_user_id
    FOREIGN KEY (user_id) REFERENCES vantrade_users(user_id)
    ON DELETE SET NULL;
    PRINT 'Foreign key created';
END TRY
BEGIN CATCH
    PRINT 'Foreign key creation failed (user_id may not exist)';
END CATCH

-- Step 8: Verify AFTER
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
PRINT 'Table is empty and ready for new analysis records';
