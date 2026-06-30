-- Rollback for migration 058.
--
-- The migration does NOT change schema (no column add, no constraint,
-- no index change) — it only backfills NULL/'' values to canonical
-- labels. The "down" therefore is informational: it documents that
-- pre-058 semantics treated NULL/'' as derived values, but cannot
-- reverse the backfill (the source values are gone).
--
-- The accompanying Go-side change (dropping requestLogStatusExpr) is
-- a separate refactor commit and is reverted by `git revert`.

-- Nothing to undo at the SQL level. The values we wrote are the
-- same values the read-side COALESCE would have produced; the table
-- is functionally identical to the pre-058 state from any consumer's
-- perspective.

DO $$
BEGIN
    RAISE NOTICE '058 rollback is a no-op: the backfill wrote the same values the COALESCE produced. Read-side git revert is required to restore the COALESCE expression.';
END $$;