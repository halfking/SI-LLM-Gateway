-- Migration: 303_sticky_sessions_unique_key.down.sql
-- Purpose: Roll back the UNIQUE constraint on sticky_sessions.sticky_key
--          added by 303_sticky_sessions_unique_key.sql.

DROP INDEX CONCURRENTLY IF EXISTS public.idx_sticky_sessions_sticky_key_unique;