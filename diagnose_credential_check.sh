#!/bin/bash
# Diagnostic script for credential check ID mismatch issue
# Usage: ./diagnose_credential_check.sh

set -e

LOG_PREFIX="[DIAGNOSE]"

echo "${LOG_PREFIX} Checking credential check ID mismatch issue"
echo "${LOG_PREFIX} ============================================="

if [ -z "${LLM_GATEWAY_DATABASE_URL:-}" ]; then
    echo "${LOG_PREFIX} ERROR: LLM_GATEWAY_DATABASE_URL not set"
    echo "${LOG_PREFIX} Please set it to: postgresql://user:[REDACTED_PASSWORD]@host:port/dbname"
    exit 1
fi

echo ""
echo "${LOG_PREFIX} 1. Checking Provider 314 and 35..."
psql "${LLM_GATEWAY_DATABASE_URL}" -c "
SELECT id, code, display_name, catalog_code, enabled
FROM providers 
WHERE id IN (314, 35)
ORDER BY id;
"

echo ""
echo "${LOG_PREFIX} 2. Checking Credential 2 and 12..."
psql "${LLM_GATEWAY_DATABASE_URL}" -c "
SELECT id, provider_id, label, status, lifecycle_status
FROM credentials 
WHERE id IN (2, 12)
ORDER BY id;
"

echo ""
echo "${LOG_PREFIX} 3. Checking recent health_check tasks for ID mismatches..."
psql "${LLM_GATEWAY_DATABASE_URL}" -c "
SELECT 
    id, 
    task_type, 
    provider_id, 
    credential_id, 
    (request_json->>'provider_id')::bigint AS req_pid,
    (request_json->>'credential_id')::bigint AS req_cid,
    status,
    started_at
FROM background_tasks 
WHERE task_type = 'health_check'
  AND ( (request_json->>'provider_id')::bigint IS DISTINCT FROM provider_id
     OR (request_json->>'credential_id')::bigint IS DISTINCT FROM credential_id )
ORDER BY id DESC 
LIMIT 20;
"

echo ""
echo "${LOG_PREFIX} 4. Checking all recent health_check tasks..."
psql "${LLM_GATEWAY_DATABASE_URL}" -c "
SELECT 
    id, 
    provider_id, 
    credential_id, 
    (request_json->>'provider_id')::bigint AS req_pid,
    (request_json->>'credential_id')::bigint AS req_cid,
    status,
    started_at
FROM background_tasks 
WHERE task_type = 'health_check'
ORDER BY id DESC 
LIMIT 10;
"

echo ""
echo "${LOG_PREFIX} ============================================="
echo "${LOG_PREFIX} Diagnosis complete!"
echo ""
echo "${LOG_PREFIX} Next steps:"
echo "${LOG_PREFIX} 1. If credential 2 belongs to provider 35 (not 314), the frontend is using wrong URL"
echo "${LOG_PREFIX} 2. If credential 2 belongs to provider 314, there's a backend routing bug"
echo "${LOG_PREFIX} 3. Check the ID mismatch section - if rows appear, there's an INSERT bug"
