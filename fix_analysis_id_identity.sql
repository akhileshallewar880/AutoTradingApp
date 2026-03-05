-- Fix analysis_id IDENTITY constraint issue
-- This script properly converts analysis_id from INT IDENTITY to VARCHAR(36)

-- Step 1: Drop the primary key constraint
ALTER TABLE vantrade_analyses
DROP CONSTRAINT PK_vantrade_analyses;

-- Step 2: Rename old column to temp
EXEC sp_rename 'vantrade_analyses.analysis_id', 'analysis_id_old';

-- Step 3: Create new analysis_id column as VARCHAR(36) WITHOUT IDENTITY
ALTER TABLE vantrade_analyses
ADD analysis_id VARCHAR(36) NULL;

-- Step 4: Copy data from old column to new column (convert INT to string)
UPDATE vantrade_analyses
SET analysis_id = CAST(analysis_id_old AS VARCHAR(36))
WHERE analysis_id_old IS NOT NULL;

-- Step 5: Drop the old column
ALTER TABLE vantrade_analyses
DROP COLUMN analysis_id_old;

-- Step 6: Set analysis_id as PRIMARY KEY (NOT NULL)
ALTER TABLE vantrade_analyses
ALTER COLUMN analysis_id VARCHAR(36) NOT NULL;

-- Step 7: Add primary key constraint
ALTER TABLE vantrade_analyses
ADD PRIMARY KEY (analysis_id);

-- Step 8: Verify the change
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    COLUMNPROPERTY(OBJECT_ID('vantrade_analyses'), COLUMN_NAME, 'IsIdentity') AS IS_IDENTITY
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vantrade_analyses'
AND COLUMN_NAME IN ('analysis_id', 'user_id');

-- Expected output:
-- analysis_id | varchar(36) | NO | 0 (0 means NOT an identity)
-- user_id | int | YES | 0
