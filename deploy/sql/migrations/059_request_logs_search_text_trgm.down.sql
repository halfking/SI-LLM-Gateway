-- Rollback for migration 059. Drops the GIN trgm index on search_text.
--
-- DROP INDEX takes an ACCESS EXCLUSIVE lock briefly; on a partitioned
-- table this propagates to all partitions. Safe to run, no data loss.

DROP INDEX IF EXISTS public.idx_request_logs_search_text_trgm;

-- Note: the db/db.go EnsureRequestLogSchema mirror will re-create the
-- index on the next gateway restart if not also reverted. To fully
-- roll back, also git revert the mirror block in db/db.go.