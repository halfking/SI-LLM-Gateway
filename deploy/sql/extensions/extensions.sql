-- ============================================
-- LLM Gateway Database Extensions
-- Generated: 2026-07-05
-- Source: Test server llm_gateway database
-- 
-- Modification Log:
-- 2026-07-05: Initial export from production database
-- 
-- Note: These extensions must be installed before running schema.sql
-- ============================================

-- Citus Columnar extension for columnar storage
CREATE EXTENSION IF NOT EXISTS citus_columnar WITH SCHEMA pg_catalog;
COMMENT ON EXTENSION citus_columnar IS 'Citus Columnar extension';

-- B-tree GiST extension for indexing common datatypes
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;
COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';

-- pgcrypto extension for cryptographic functions
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';
