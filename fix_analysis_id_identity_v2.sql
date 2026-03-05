-- Fix analysis_id IDENTITY constraint issue - Version 2
-- Simpler approach: directly remove IDENTITY property

-- Step 1: Check current schema
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    COLUMNPROPERTY(OBJECT_ID('vantrade_analyses'), COLUMN_NAME, 'IsIdentity') AS IS_IDENTITY
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vantrade_analyses'
AND COLUMN_NAME IN ('analysis_id', 'user_id');

-- Step 2: Drop the primary key (if it exists)
BEGIN TRY
    ALTER TABLE vantrade_analyses
    DROP CONSTRAINT PK_vantrade_analyses;
    PRINT 'Primary key dropped';
END TRY
BEGIN CATCH
    PRINT 'Primary key does not exist or could not be dropped';
END CATCH

-- Step 3: Drop foreign key on user_id (if it exists)
BEGIN TRY
    ALTER TABLE vantrade_analyses
    DROP CONSTRAINT FK_vantrade_analyses_user_id;
    PRINT 'Foreign key dropped';
END TRY
BEGIN CATCH
    PRINT 'Foreign key does not exist or could not be dropped';
END CATCH

-- Step 4: Drop analysis_id column and recreate it WITHOUT IDENTITY
BEGIN TRY
    ALTER TABLE vantrade_analyses
    DROP COLUMN analysis_id;
    PRINT 'Old analysis_id column dropped';
END TRY
BEGIN CATCH
    PRINT 'Could not drop analysis_id column';
END CATCH

-- Step 5: Add analysis_id column as VARCHAR(36) NOT NULL PRIMARY KEY
ALTER TABLE vantrade_analyses
ADD analysis_id VARCHAR(36) NOT NULL PRIMARY KEY;

-- Step 6: Make user_id nullable
ALTER TABLE vantrade_analyses
ALTER COLUMN user_id INT NULL;

-- Step 7: Recreate foreign key
BEGIN TRY
    ALTER TABLE vantrade_analyses
    ADD CONSTRAINT FK_vantrade_analyses_user_id
    FOREIGN KEY (user_id) REFERENCES vantrade_users(user_id)
    ON DELETE SET NULL;
    PRINT 'Foreign key recreated';
END TRY
BEGIN CATCH
    PRINT 'Could not recreate foreign key';
END CATCH

-- Step 8: Verify the final schema
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

-- Expected output:
-- analysis_id | varchar(36) | NO  | 0 (0 = NOT IDENTITY)
-- user_id     | int         | YES | 0
