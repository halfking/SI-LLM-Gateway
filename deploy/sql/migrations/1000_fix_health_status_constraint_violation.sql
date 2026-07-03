-- Migration: Fix health_status constraint violation
-- Date: 2026-07-03
-- Issue: credentials.health_status was set to 'error' which violates 
--        chk_credentials_health_status CHECK constraint
-- Fix: Replace 'error' with 'unreachable' to comply with the constraint
--      (allowed values: 'unknown', 'healthy', 'warning', 'unreachable')

BEGIN;

-- Update any existing 'error' values to 'unreachable'
UPDATE credentials 
SET health_status = 'unreachable' 
WHERE health_status = 'error';

-- Log the fix
DO $$
DECLARE
    affected_count INTEGER;
BEGIN
    GET DIAGNOSTICS affected_count = ROW_COUNT;
    IF affected_count > 0 THEN
        RAISE NOTICE 'Fixed % credentials with health_status=''error'' -> ''unreachable''', affected_count;
    ELSE
        RAISE NOTICE 'No credentials with invalid health_status found';
    END IF;
END $$;

COMMIT;
