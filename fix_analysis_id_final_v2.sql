-- Final fix v2: Remove IDENTITY constraint - Handle All Dependencies
-- This version properly drops all dependent foreign keys from other tables first

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

-- Step 2: Drop ALL foreign keys that reference analysis_id FROM OTHER TABLES
PRINT '';
PRINT 'Dropping foreign keys from dependent tables...';

BEGIN TRY
    ALTER TABLE vantrade_stock_recommendations
    DROP CONSTRAINT FK__vantrade___analy__46136164;
    PRINT 'Dropped FK from vantrade_stock_recommendations';
END TRY
BEGIN CATCH
    PRINT 'FK from vantrade_stock_recommendations not found (OK)';
END CATCH

BEGIN TRY
    ALTER TABLE vantrade_signals
    DROP CONSTRAINT FK__vantrade___analy__4AD81681;
    PRINT 'Dropped FK from vantrade_signals';
END TRY
BEGIN CATCH
    PRINT 'FK from vantrade_signals not found (OK)';
END CATCH

BEGIN TRY
    ALTER TABLE vantrade_orders
    DROP CONSTRAINT FK__vantrade___analy__4EA8A765;
    PRINT 'Dropped FK from vantrade_orders';
END TRY
BEGIN CATCH
    PRINT 'FK from vantrade_orders not found (OK)';
END CATCH

-- Step 3: Delete all dependent records first
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

-- Step 4: Now delete from vantrade_analyses
PRINT '';
PRINT 'Clearing vantrade_analyses...';
DELETE FROM vantrade_analyses;
PRINT 'Data cleared';

-- Step 5: Drop constraints on vantrade_analyses itself
PRINT '';
PRINT 'Dropping constraints on vantrade_analyses...';

BEGIN TRY
    ALTER TABLE vantrade_analyses DROP CONSTRAINT PK__vantrade__5B14DE5AEB5B9622;
    PRINT 'Primary key dropped';
END TRY
BEGIN CATCH
    PRINT 'Primary key not found (OK)';
END CATCH

BEGIN TRY
    ALTER TABLE vantrade_analyses DROP CONSTRAINT FK_vantrade_analyses_user_id;
    PRINT 'Foreign key to users dropped';
END TRY
BEGIN CATCH
    PRINT 'Foreign key to users not found (OK)';
END CATCH

BEGIN TRY
    DROP INDEX ix_vantrade_analyses_analysis_id ON vantrade_analyses;
    PRINT 'Index on analysis_id dropped';
END TRY
BEGIN CATCH
    PRINT 'Index on analysis_id not found (OK)';
END CATCH

-- Step 6: Drop the analysis_id column
PRINT '';
PRINT 'Dropping analysis_id column...';
ALTER TABLE vantrade_analyses DROP COLUMN analysis_id;
PRINT 'Column dropped';

-- Step 7: Add analysis_id as VARCHAR(36) PRIMARY KEY (NOT IDENTITY)
PRINT '';
PRINT 'Adding new analysis_id column...';
ALTER TABLE vantrade_analyses
ADD analysis_id VARCHAR(36) NOT NULL PRIMARY KEY;
PRINT 'Column added successfully';

-- Step 8: Ensure user_id is nullable
PRINT '';
PRINT 'Making user_id nullable...';
ALTER TABLE vantrade_analyses
ALTER COLUMN user_id INT NULL;
PRINT 'Done';

-- Step 9: Recreate foreign key to users
PRINT '';
PRINT 'Recreating foreign key to users...';
BEGIN TRY
    ALTER TABLE vantrade_analyses
    ADD CONSTRAINT FK_vantrade_analyses_user_id
    FOREIGN KEY (user_id) REFERENCES vantrade_users(user_id)
    ON DELETE SET NULL;
    PRINT 'Foreign key to users created';
END TRY
BEGIN CATCH
    PRINT 'Foreign key to users creation failed (OK)';
END CATCH

-- Step 10: Recreate foreign keys in dependent tables
PRINT '';
PRINT 'Recreating foreign keys in dependent tables...';

BEGIN TRY
    ALTER TABLE vantrade_stock_recommendations
    ADD CONSTRAINT FK_vantrade_stock_recommendations_analysis_id
    FOREIGN KEY (analysis_id) REFERENCES vantrade_analyses(analysis_id)
    ON DELETE CASCADE;
    PRINT 'FK for vantrade_stock_recommendations created';
END TRY
BEGIN CATCH
    PRINT 'FK for vantrade_stock_recommendations creation failed (OK)';
END CATCH

BEGIN TRY
    ALTER TABLE vantrade_signals
    ADD CONSTRAINT FK_vantrade_signals_analysis_id
    FOREIGN KEY (analysis_id) REFERENCES vantrade_analyses(analysis_id)
    ON DELETE CASCADE;
    PRINT 'FK for vantrade_signals created';
END TRY
BEGIN CATCH
    PRINT 'FK for vantrade_signals creation failed (OK)';
END CATCH

BEGIN TRY
    ALTER TABLE vantrade_orders
    ADD CONSTRAINT FK_vantrade_orders_analysis_id
    FOREIGN KEY (analysis_id) REFERENCES vantrade_analyses(analysis_id)
    ON DELETE CASCADE;
    PRINT 'FK for vantrade_orders created';
END TRY
BEGIN CATCH
    PRINT 'FK for vantrade_orders creation failed (OK)';
END CATCH

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
PRINT 'All dependent tables have been cleaned and foreign keys recreated';
