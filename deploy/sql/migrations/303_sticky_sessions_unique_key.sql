-- Migration: 303_sticky_sessions_unique_key.sql
-- Purpose: Add UNIQUE constraint on sticky_sessions.sticky_key so that
--          ON CONFLICT (sticky_key) DO UPDATE in routing/sticky.go
--          actually works.
-- Date: 2026-07-02
-- Issue: gateway log repeatedly shows
--   `sticky DB write failed: there is no unique or exclusion
--    constraint matching the ON CONFLICT specification (SQLSTATE 42P10)`
--   because sticky_sessions was created without any UNIQUE/PRIMARY KEY
--   on sticky_key. Every successful request that triggered a sticky
--   write failed silently (slog.Debug only), losing the cross-process
--   sticky credential binding.
--
-- Strategy:
--   1. Inspect existing data for duplicates (defensive guard).
--   2. Add UNIQUE constraint via CREATE UNIQUE INDEX CONCURRENTLY.
--      CONCURRENTLY is required to avoid blocking writes on a hot table.
--   3. Re-verify the constraint is in place.
--
-- Rollback: 303_sticky_sessions_unique_key.down.sql drops the index.

-- Step 1: surface any pre-existing duplicates before adding the constraint.
-- If this returns > 0 rows the migration will still succeed because
-- CREATE UNIQUE INDEX will fail on duplicates; we surface that fact
-- loudly to operators and pick a deterministic tie-breaker (latest
-- set_at wins).
DO $$
DECLARE
    dup_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO dup_count
    FROM (
        SELECT sticky_key
        FROM public.sticky_sessions
        GROUP BY sticky_key
        HAVING COUNT(*) > 1
    ) dups;

    IF dup_count > 0 THEN
        RAISE NOTICE 'sticky_sessions: % duplicate keys detected before adding UNIQUE; de-duping by keeping latest set_at per key',
            dup_count;

        -- Keep the most-recent row per key, delete the rest.
        DELETE FROM public.sticky_sessions ss
        USING public.sticky_sessions newer
        WHERE ss.sticky_key = newer.sticky_key
          AND ss.set_at < newer.set_at;
    END IF;
END $$;

-- Step 2: add the unique index concurrently (non-blocking on PG 11+).
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_sticky_sessions_sticky_key_unique
    ON public.sticky_sessions (sticky_key);

-- Step 3: sanity check (the operator can verify on a follow-up query).
DO $$
DECLARE
    has_unique BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename  = 'sticky_sessions'
          AND indexname  = 'idx_sticky_sessions_sticky_key_unique'
    ) INTO has_unique;

    IF NOT has_unique THEN
        RAISE EXCEPTION 'idx_sticky_sessions_sticky_key_unique missing after CREATE UNIQUE INDEX CONCURRENTLY';
    END IF;

    RAISE NOTICE 'sticky_sessions: UNIQUE(sticky_key) added successfully';
END $$;