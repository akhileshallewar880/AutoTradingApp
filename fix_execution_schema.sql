-- ============================================================
-- Migration: fix_execution_schema
-- Run this directly in SSMS / Azure Data Studio
-- ============================================================

-- 1. Add quantity column to vantrade_stock_recommendations
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vantrade_stock_recommendations'
      AND COLUMN_NAME = 'quantity'
)
BEGIN
    ALTER TABLE vantrade_stock_recommendations
    ADD quantity INT NOT NULL DEFAULT 1;
    PRINT '✅ Added quantity to vantrade_stock_recommendations';
END
ELSE
    PRINT '⏭ quantity already exists in vantrade_stock_recommendations';

-- 2. Add message column to vantrade_execution_updates
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vantrade_execution_updates'
      AND COLUMN_NAME = 'message'
)
BEGIN
    ALTER TABLE vantrade_execution_updates ADD message NVARCHAR(MAX) NULL;
    PRINT '✅ Added message to vantrade_execution_updates';
END
ELSE
    PRINT '⏭ message already exists in vantrade_execution_updates';

-- 3. Add order_id column to vantrade_execution_updates
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vantrade_execution_updates'
      AND COLUMN_NAME = 'order_id'
)
BEGIN
    ALTER TABLE vantrade_execution_updates ADD order_id NVARCHAR(255) NULL;
    PRINT '✅ Added order_id to vantrade_execution_updates';
END
ELSE
    PRINT '⏭ order_id already exists in vantrade_execution_updates';

-- 4. Add status column to vantrade_execution_updates
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vantrade_execution_updates'
      AND COLUMN_NAME = 'status'
)
BEGIN
    ALTER TABLE vantrade_execution_updates ADD status NVARCHAR(50) NULL;
    PRINT '✅ Added status to vantrade_execution_updates';
END
ELSE
    PRINT '⏭ status already exists in vantrade_execution_updates';

-- 5. Add timestamp column to vantrade_execution_updates
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vantrade_execution_updates'
      AND COLUMN_NAME = 'timestamp'
)
BEGIN
    ALTER TABLE vantrade_execution_updates ADD timestamp DATETIME2 NULL;
    PRINT '✅ Added timestamp to vantrade_execution_updates';
END
ELSE
    PRINT '⏭ timestamp already exists in vantrade_execution_updates';

-- 6. Widen update_type to accept free-form strings (not enum-restricted)
--    Safe: only changes max length, no data loss
IF EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vantrade_execution_updates'
      AND COLUMN_NAME = 'update_type'
)
BEGIN
    ALTER TABLE vantrade_execution_updates
    ALTER COLUMN update_type NVARCHAR(100) NOT NULL;
    PRINT '✅ Widened update_type column in vantrade_execution_updates';
END

-- 7. Fix analysis_id type in child tables (int → varchar(36)) if not already fixed
--    vantrade_stock_recommendations
IF EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vantrade_stock_recommendations'
      AND COLUMN_NAME = 'analysis_id'
      AND DATA_TYPE = 'int'
)
BEGIN
    -- Drop FK first if it exists
    DECLARE @fk1 NVARCHAR(256);
    SELECT @fk1 = fk.name
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    JOIN sys.columns c ON fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id
    WHERE OBJECT_NAME(fk.parent_object_id) = 'vantrade_stock_recommendations'
      AND c.name = 'analysis_id';
    IF @fk1 IS NOT NULL EXEC('ALTER TABLE vantrade_stock_recommendations DROP CONSTRAINT ' + @fk1);

    ALTER TABLE vantrade_stock_recommendations
    ALTER COLUMN analysis_id NVARCHAR(36) NOT NULL;

    IF @fk1 IS NOT NULL
        ALTER TABLE vantrade_stock_recommendations
        ADD CONSTRAINT FK_recommendations_analysis
        FOREIGN KEY (analysis_id) REFERENCES vantrade_analyses(analysis_id);

    PRINT '✅ Fixed analysis_id type in vantrade_stock_recommendations';
END
ELSE
    PRINT '⏭ analysis_id already correct type in vantrade_stock_recommendations';

--    vantrade_execution_updates
IF EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vantrade_execution_updates'
      AND COLUMN_NAME = 'analysis_id'
      AND DATA_TYPE = 'int'
)
BEGIN
    DECLARE @fk2 NVARCHAR(256);
    SELECT @fk2 = fk.name
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    JOIN sys.columns c ON fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id
    WHERE OBJECT_NAME(fk.parent_object_id) = 'vantrade_execution_updates'
      AND c.name = 'analysis_id';
    IF @fk2 IS NOT NULL EXEC('ALTER TABLE vantrade_execution_updates DROP CONSTRAINT ' + @fk2);

    ALTER TABLE vantrade_execution_updates
    ALTER COLUMN analysis_id NVARCHAR(36) NOT NULL;

    IF @fk2 IS NOT NULL
        ALTER TABLE vantrade_execution_updates
        ADD CONSTRAINT FK_execution_updates_analysis
        FOREIGN KEY (analysis_id) REFERENCES vantrade_analyses(analysis_id);

    PRINT '✅ Fixed analysis_id type in vantrade_execution_updates';
END
ELSE
    PRINT '⏭ analysis_id already correct type in vantrade_execution_updates';

--    vantrade_orders
IF EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vantrade_orders'
      AND COLUMN_NAME = 'analysis_id'
      AND DATA_TYPE = 'int'
)
BEGIN
    DECLARE @fk3 NVARCHAR(256);
    SELECT @fk3 = fk.name
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    JOIN sys.columns c ON fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id
    WHERE OBJECT_NAME(fk.parent_object_id) = 'vantrade_orders'
      AND c.name = 'analysis_id';
    IF @fk3 IS NOT NULL EXEC('ALTER TABLE vantrade_orders DROP CONSTRAINT ' + @fk3);

    ALTER TABLE vantrade_orders
    ALTER COLUMN analysis_id NVARCHAR(36) NOT NULL;

    IF @fk3 IS NOT NULL
        ALTER TABLE vantrade_orders
        ADD CONSTRAINT FK_orders_analysis
        FOREIGN KEY (analysis_id) REFERENCES vantrade_analyses(analysis_id);

    PRINT '✅ Fixed analysis_id type in vantrade_orders';
END
ELSE
    PRINT '⏭ analysis_id already correct type in vantrade_orders';

-- Done
PRINT '';
PRINT '✅ All migrations applied successfully.';
