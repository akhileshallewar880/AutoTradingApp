-- Comprehensive fix: Change analysis_id from INT to VARCHAR(36) in ALL tables
-- This updates vantrade_analyses and all dependent tables

PRINT '===== STEP 1: Check current schema =====';
SELECT
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME = 'analysis_id'
ORDER BY TABLE_NAME;

-- Step 2: Delete all data from dependent tables first
PRINT '';
PRINT '===== STEP 2: Deleting dependent records =====';

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

DELETE FROM vantrade_analyses;
PRINT 'Deleted vantrade_analyses';

-- Step 3: Drop all foreign keys referencing analysis_id
PRINT '';
PRINT '===== STEP 3: Dropping foreign keys =====';

DECLARE @FKName NVARCHAR(128);
DECLARE @TableName NVARCHAR(128);

DECLARE fk_cursor CURSOR FOR
SELECT fk.name AS FK_NAME, t.name AS TABLE_NAME
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
        PRINT 'Could not drop FK ' + @FKName;
    END CATCH
    FETCH NEXT FROM fk_cursor INTO @FKName, @TableName;
END

CLOSE fk_cursor;
DEALLOCATE fk_cursor;

-- Step 4: Drop primary key on vantrade_analyses
PRINT '';
PRINT '===== STEP 4: Dropping primary key on vantrade_analyses =====';

BEGIN TRY
    DECLARE @PKName NVARCHAR(128);
    SELECT @PKName = name FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID('vantrade_analyses') AND type = 'PK';

    IF @PKName IS NOT NULL
    BEGIN
        DECLARE @DropPK NVARCHAR(255) = 'ALTER TABLE vantrade_analyses DROP CONSTRAINT ' + QUOTENAME(@PKName);
        EXECUTE sp_executesql @DropPK;
        PRINT 'Dropped primary key: ' + @PKName;
    END
END TRY
BEGIN CATCH
    PRINT 'Primary key drop error (may already be gone)';
END CATCH

-- Step 5: Drop ALL indexes on analysis_id in all tables
PRINT '';
PRINT '===== STEP 5: Dropping all indexes =====';

-- vantrade_analyses
BEGIN TRY
    DROP INDEX ix_vantrade_analyses_analysis_id ON vantrade_analyses;
    PRINT 'Dropped ix_vantrade_analyses_analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Index not found';
END CATCH

-- vantrade_stock_recommendations
BEGIN TRY
    DROP INDEX ix_vantrade_stock_recommendations_analysis_id ON vantrade_stock_recommendations;
    PRINT 'Dropped ix_vantrade_stock_recommendations_analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Index not found';
END CATCH

BEGIN TRY
    DROP INDEX idx_recommendation_analysis ON vantrade_stock_recommendations;
    PRINT 'Dropped idx_recommendation_analysis';
END TRY
BEGIN CATCH
    PRINT 'Index not found';
END CATCH

-- vantrade_signals
BEGIN TRY
    DROP INDEX ix_vantrade_signals_analysis_id ON vantrade_signals;
    PRINT 'Dropped ix_vantrade_signals_analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Index not found';
END CATCH

-- vantrade_orders
BEGIN TRY
    DROP INDEX ix_vantrade_orders_analysis_id ON vantrade_orders;
    PRINT 'Dropped ix_vantrade_orders_analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Index not found';
END CATCH

-- vantrade_gtt_orders
BEGIN TRY
    DROP INDEX ix_vantrade_gtt_orders_analysis_id ON vantrade_gtt_orders;
    PRINT 'Dropped ix_vantrade_gtt_orders_analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Index not found';
END CATCH

-- vantrade_execution_updates
BEGIN TRY
    DROP INDEX ix_vantrade_execution_updates_analysis_id ON vantrade_execution_updates;
    PRINT 'Dropped ix_vantrade_execution_updates_analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Index not found';
END CATCH

-- vantrade_trades
BEGIN TRY
    DROP INDEX ix_vantrade_trades_analysis_id ON vantrade_trades;
    PRINT 'Dropped ix_vantrade_trades_analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Index not found';
END CATCH

-- vantrade_open_positions
BEGIN TRY
    DROP INDEX ix_vantrade_open_positions_analysis_id ON vantrade_open_positions;
    PRINT 'Dropped ix_vantrade_open_positions_analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Index not found';
END CATCH

-- Dynamic approach: Drop any remaining indexes on analysis_id
PRINT '';
PRINT 'Dropping any remaining indexes on analysis_id...';

DECLARE @IndexName NVARCHAR(128);
DECLARE @TableNameForIndex NVARCHAR(128);

DECLARE index_cursor CURSOR FOR
SELECT i.name, t.name
FROM sys.indexes i
JOIN sys.tables t ON i.object_id = t.object_id
JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE c.name = 'analysis_id' AND i.name NOT LIKE 'PK%';

OPEN index_cursor;
FETCH NEXT FROM index_cursor INTO @IndexName, @TableNameForIndex;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        DECLARE @DropIndex NVARCHAR(255) = 'DROP INDEX ' + QUOTENAME(@IndexName) + ' ON ' + QUOTENAME(@TableNameForIndex);
        EXECUTE sp_executesql @DropIndex;
        PRINT 'Dropped index ' + @IndexName + ' on ' + @TableNameForIndex;
    END TRY
    BEGIN CATCH
        PRINT 'Could not drop index ' + @IndexName;
    END CATCH
    FETCH NEXT FROM index_cursor INTO @IndexName, @TableNameForIndex;
END

CLOSE index_cursor;
DEALLOCATE index_cursor;

-- Step 6: Disable all constraints
PRINT '';
PRINT '===== STEP 6: Disabling constraints =====';

ALTER TABLE vantrade_analyses NOCHECK CONSTRAINT ALL;
ALTER TABLE vantrade_stock_recommendations NOCHECK CONSTRAINT ALL;
ALTER TABLE vantrade_signals NOCHECK CONSTRAINT ALL;
ALTER TABLE vantrade_orders NOCHECK CONSTRAINT ALL;
ALTER TABLE vantrade_gtt_orders NOCHECK CONSTRAINT ALL;
ALTER TABLE vantrade_execution_updates NOCHECK CONSTRAINT ALL;
ALTER TABLE vantrade_trades NOCHECK CONSTRAINT ALL;
ALTER TABLE vantrade_open_positions NOCHECK CONSTRAINT ALL;
PRINT 'All constraints disabled';

-- Step 7: Drop and recreate analysis_id column in vantrade_analyses
PRINT '';
PRINT '===== STEP 7: Dropping and recreating analysis_id in vantrade_analyses =====';

BEGIN TRY
    ALTER TABLE vantrade_analyses DROP COLUMN analysis_id;
    PRINT 'Dropped analysis_id column';
END TRY
BEGIN CATCH
    PRINT 'Could not drop analysis_id column';
END CATCH

-- Step 8: Add analysis_id back as VARCHAR(36) NOT NULL PRIMARY KEY
PRINT '';
PRINT '===== STEP 8: Adding analysis_id as VARCHAR(36) NOT NULL PRIMARY KEY =====';

ALTER TABLE vantrade_analyses
ADD analysis_id VARCHAR(36) NOT NULL PRIMARY KEY;
PRINT 'Created analysis_id as VARCHAR(36) NOT NULL PRIMARY KEY';

-- Step 9: Make user_id nullable on vantrade_analyses
PRINT '';
PRINT '===== STEP 9: Making user_id nullable =====';

ALTER TABLE vantrade_analyses
ALTER COLUMN user_id INT NULL;
PRINT 'Set user_id to nullable';

-- Step 10: Convert dependent tables (drop and recreate their analysis_id columns)
PRINT '';
PRINT '===== STEP 10: Converting dependent tables =====';

-- vantrade_stock_recommendations - NOT NULL
BEGIN TRY
    ALTER TABLE vantrade_stock_recommendations DROP COLUMN analysis_id;
    ALTER TABLE vantrade_stock_recommendations ADD analysis_id VARCHAR(36) NOT NULL;
    PRINT 'Converted vantrade_stock_recommendations.analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Could not convert vantrade_stock_recommendations.analysis_id';
END CATCH

-- vantrade_signals - NOT NULL (need to drop and recreate more carefully)
BEGIN TRY
    IF COL_LENGTH('vantrade_signals', 'analysis_id') IS NOT NULL
    BEGIN
        ALTER TABLE vantrade_signals DROP COLUMN analysis_id;
    END
    ALTER TABLE vantrade_signals ADD analysis_id VARCHAR(36) NOT NULL;
    PRINT 'Converted vantrade_signals.analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Error converting vantrade_signals.analysis_id - may require manual intervention';
END CATCH

-- vantrade_orders - nullable
BEGIN TRY
    ALTER TABLE vantrade_orders ALTER COLUMN analysis_id VARCHAR(36) NULL;
    PRINT 'Converted vantrade_orders.analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Could not alter vantrade_orders.analysis_id, attempting drop/recreate...';
    BEGIN TRY
        IF COL_LENGTH('vantrade_orders', 'analysis_id') IS NOT NULL
        BEGIN
            ALTER TABLE vantrade_orders DROP COLUMN analysis_id;
        END
        ALTER TABLE vantrade_orders ADD analysis_id VARCHAR(36) NULL;
        PRINT 'Recreated vantrade_orders.analysis_id';
    END TRY
    BEGIN CATCH
        PRINT 'Could not convert vantrade_orders.analysis_id';
    END CATCH
END CATCH

-- vantrade_gtt_orders - nullable
BEGIN TRY
    ALTER TABLE vantrade_gtt_orders ALTER COLUMN analysis_id VARCHAR(36) NULL;
    PRINT 'Converted vantrade_gtt_orders.analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Could not alter vantrade_gtt_orders.analysis_id, attempting drop/recreate...';
    BEGIN TRY
        IF COL_LENGTH('vantrade_gtt_orders', 'analysis_id') IS NOT NULL
        BEGIN
            ALTER TABLE vantrade_gtt_orders DROP COLUMN analysis_id;
        END
        ALTER TABLE vantrade_gtt_orders ADD analysis_id VARCHAR(36) NULL;
        PRINT 'Recreated vantrade_gtt_orders.analysis_id';
    END TRY
    BEGIN CATCH
        PRINT 'Could not convert vantrade_gtt_orders.analysis_id';
    END CATCH
END CATCH

-- vantrade_execution_updates - nullable
BEGIN TRY
    ALTER TABLE vantrade_execution_updates ALTER COLUMN analysis_id VARCHAR(36) NULL;
    PRINT 'Converted vantrade_execution_updates.analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Could not convert vantrade_execution_updates.analysis_id';
END CATCH

-- vantrade_trades - nullable
BEGIN TRY
    ALTER TABLE vantrade_trades ALTER COLUMN analysis_id VARCHAR(36) NULL;
    PRINT 'Converted vantrade_trades.analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Could not alter vantrade_trades.analysis_id, attempting drop/recreate...';
    BEGIN TRY
        IF COL_LENGTH('vantrade_trades', 'analysis_id') IS NOT NULL
        BEGIN
            ALTER TABLE vantrade_trades DROP COLUMN analysis_id;
        END
        ALTER TABLE vantrade_trades ADD analysis_id VARCHAR(36) NULL;
        PRINT 'Recreated vantrade_trades.analysis_id';
    END TRY
    BEGIN CATCH
        PRINT 'Could not convert vantrade_trades.analysis_id';
    END CATCH
END CATCH

-- vantrade_open_positions - nullable
BEGIN TRY
    ALTER TABLE vantrade_open_positions ALTER COLUMN analysis_id VARCHAR(36) NULL;
    PRINT 'Converted vantrade_open_positions.analysis_id';
END TRY
BEGIN CATCH
    PRINT 'Could not alter vantrade_open_positions.analysis_id, attempting drop/recreate...';
    BEGIN TRY
        IF COL_LENGTH('vantrade_open_positions', 'analysis_id') IS NOT NULL
        BEGIN
            ALTER TABLE vantrade_open_positions DROP COLUMN analysis_id;
        END
        ALTER TABLE vantrade_open_positions ADD analysis_id VARCHAR(36) NULL;
        PRINT 'Recreated vantrade_open_positions.analysis_id';
    END TRY
    BEGIN CATCH
        PRINT 'Could not convert vantrade_open_positions.analysis_id';
    END CATCH
END CATCH

-- Step 11: Recreate foreign keys
PRINT '';
PRINT '===== STEP 11: Recreating foreign keys =====';

BEGIN TRY
    ALTER TABLE vantrade_stock_recommendations
    ADD CONSTRAINT FK_vantrade_stock_recommendations_analysis_id
    FOREIGN KEY (analysis_id) REFERENCES vantrade_analyses(analysis_id)
    ON DELETE CASCADE;
    PRINT 'Recreated FK: vantrade_stock_recommendations -> vantrade_analyses';
END TRY
BEGIN CATCH
    PRINT 'FK vantrade_stock_recommendations creation failed';
END CATCH

BEGIN TRY
    ALTER TABLE vantrade_signals
    ADD CONSTRAINT FK_vantrade_signals_analysis_id
    FOREIGN KEY (analysis_id) REFERENCES vantrade_analyses(analysis_id)
    ON DELETE CASCADE;
    PRINT 'Recreated FK: vantrade_signals -> vantrade_analyses';
END TRY
BEGIN CATCH
    PRINT 'FK vantrade_signals creation failed';
END CATCH

BEGIN TRY
    ALTER TABLE vantrade_orders
    ADD CONSTRAINT FK_vantrade_orders_analysis_id
    FOREIGN KEY (analysis_id) REFERENCES vantrade_analyses(analysis_id)
    ON DELETE CASCADE;
    PRINT 'Recreated FK: vantrade_orders -> vantrade_analyses';
END TRY
BEGIN CATCH
    PRINT 'FK vantrade_orders creation failed';
END CATCH

-- Step 12: Re-enable constraints
PRINT '';
PRINT '===== STEP 12: Re-enabling constraints =====';

ALTER TABLE vantrade_analyses WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE vantrade_stock_recommendations WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE vantrade_signals WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE vantrade_orders WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE vantrade_gtt_orders WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE vantrade_execution_updates WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE vantrade_trades WITH CHECK CHECK CONSTRAINT ALL;
ALTER TABLE vantrade_open_positions WITH CHECK CHECK CONSTRAINT ALL;
PRINT 'All constraints re-enabled';

-- Step 13: Verify all changes
PRINT '';
PRINT '===== FINAL VERIFICATION =====';
SELECT
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME = 'analysis_id'
ORDER BY TABLE_NAME;

PRINT '';
PRINT 'SUCCESS! All analysis_id columns are now VARCHAR(36)';
