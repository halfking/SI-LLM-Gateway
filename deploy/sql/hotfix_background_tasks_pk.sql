-- Hotfix: Add primary key constraint to background_tasks table
-- Issue: Task ID 96 has duplicate rows causing frontend assertion failures
-- Root cause: background_tasks table missing PRIMARY KEY constraint
-- 
-- This script:
-- 1. Checks for duplicate IDs
-- 2. Removes duplicates (keeps the latest row)
-- 3. Adds PRIMARY KEY constraint
-- 4. Ensures sequence is properly configured

-- Step 1: Report duplicate IDs
DO $$
DECLARE
    dup_count INT;
BEGIN
    SELECT COUNT(*) INTO dup_count
    FROM (
        SELECT id, COUNT(*) as cnt
        FROM background_tasks
        GROUP BY id
        HAVING COUNT(*) > 1
    ) dups;
    
    IF dup_count > 0 THEN
        RAISE NOTICE 'Found % duplicate task IDs', dup_count;
        RAISE NOTICE 'Listing duplicates:';
    ELSE
        RAISE NOTICE 'No duplicate task IDs found';
    END IF;
END $$;

-- Show duplicate rows
SELECT 
    id,
    task_type,
    provider_id,
    credential_id,
    started_at,
    finished_at,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY started_at DESC) as row_num
FROM background_tasks
WHERE id IN (
    SELECT id
    FROM background_tasks
    GROUP BY id
    HAVING COUNT(*) > 1
)
ORDER BY id, started_at DESC;

-- Step 2: Create temporary table with unique IDs (keep latest by started_at)
CREATE TEMP TABLE background_tasks_deduped AS
SELECT DISTINCT ON (id) *
FROM background_tasks
ORDER BY id, started_at DESC;

-- Step 3: Backup duplicates to a separate table for audit
CREATE TABLE IF NOT EXISTS background_tasks_duplicates (
    LIKE background_tasks,
    removed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert duplicates (older rows) into backup table
INSERT INTO background_tasks_duplicates
SELECT 
    bt.*,
    NOW() as removed_at
FROM background_tasks bt
WHERE (id, started_at) NOT IN (
    SELECT id, started_at
    FROM background_tasks_deduped
);

-- Step 4: Delete all rows from original table
DELETE FROM background_tasks;

-- Step 5: Insert deduplicated rows back
INSERT INTO background_tasks
SELECT * FROM background_tasks_deduped;

-- Step 6: Add primary key constraint
ALTER TABLE background_tasks
ADD CONSTRAINT background_tasks_pkey PRIMARY KEY (id);

-- Step 7: Ensure sequence exists and is properly linked
DO $$
BEGIN
    -- Check if sequence exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_class 
        WHERE relname = 'background_tasks_id_seq' 
        AND relkind = 'S'
    ) THEN
        -- Create sequence if missing
        CREATE SEQUENCE background_tasks_id_seq;
        
        -- Set sequence to max(id) + 1
        PERFORM setval('background_tasks_id_seq', 
            COALESCE((SELECT MAX(id) FROM background_tasks), 0) + 1, 
            false);
        
        -- Link sequence to column
        ALTER TABLE background_tasks 
        ALTER COLUMN id SET DEFAULT nextval('background_tasks_id_seq');
        
        RAISE NOTICE 'Created and linked sequence background_tasks_id_seq';
    ELSE
        -- Sync existing sequence
        PERFORM setval('background_tasks_id_seq', 
            COALESCE((SELECT MAX(id) FROM background_tasks), 0) + 1, 
            false);
        
        RAISE NOTICE 'Synced existing sequence background_tasks_id_seq';
    END IF;
END $$;

-- Step 8: Verify fix
DO $$
DECLARE
    dup_count INT;
    has_pk BOOL;
    seq_val BIGINT;
    max_id BIGINT;
BEGIN
    -- Check duplicates
    SELECT COUNT(*) INTO dup_count
    FROM (
        SELECT id, COUNT(*) as cnt
        FROM background_tasks
        GROUP BY id
        HAVING COUNT(*) > 1
    ) dups;
    
    -- Check primary key
    SELECT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'background_tasks_pkey'
        AND conrelid = 'background_tasks'::regclass
    ) INTO has_pk;
    
    -- Check sequence
    SELECT last_value INTO seq_val
    FROM background_tasks_id_seq;
    
    SELECT MAX(id) INTO max_id
    FROM background_tasks;
    
    RAISE NOTICE '=== Verification Results ===';
    RAISE NOTICE 'Duplicate IDs remaining: %', dup_count;
    RAISE NOTICE 'Primary key exists: %', has_pk;
    RAISE NOTICE 'Current max ID: %', max_id;
    RAISE NOTICE 'Sequence next value: %', seq_val;
    
    IF dup_count = 0 AND has_pk THEN
        RAISE NOTICE 'SUCCESS: background_tasks table is now fixed!';
    ELSE
        RAISE WARNING 'FAILED: Issues remain, manual intervention required';
    END IF;
END $$;

-- Step 9: Show summary
SELECT 
    'Total tasks' as metric,
    COUNT(*) as value
FROM background_tasks
UNION ALL
SELECT 
    'Removed duplicates',
    COUNT(*)
FROM background_tasks_duplicates;
