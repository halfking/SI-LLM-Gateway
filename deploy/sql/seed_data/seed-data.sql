-- ============================================
-- LLM Gateway Database Seed Data
-- Generated: 2026-07-05
-- Source: Test server llm_gateway database
-- 
-- Modification Log:
-- 2026-07-05: Initial export from production database
-- 
-- Note: This file contains minimal seed data for system initialization.
-- It does NOT contain production user data, credentials, or sensitive information.
-- ============================================

-- Schema migrations tracking
-- This table tracks applied migrations to prevent duplicate execution
INSERT INTO schema_migrations (version, applied_at) VALUES
  ('20260101000001', NOW()),
  ('20260101000002', NOW())
ON CONFLICT (version) DO NOTHING;

-- Default system settings (non-sensitive only)
-- Note: Production values should be configured separately
INSERT INTO settings_kv (key, value, created_at, updated_at) VALUES
  ('system.initialized', 'true', NOW(), NOW()),
  ('system.version', '3.2.1', NOW(), NOW())
ON CONFLICT (key) DO NOTHING;

-- Tool categories for tool registry
INSERT INTO tool_categories (id, name, description, created_at) VALUES
  ('system', 'System Tools', 'Built-in system tools', NOW()),
  ('integration', 'Integration Tools', 'Third-party integration tools', NOW()),
  ('custom', 'Custom Tools', 'User-defined custom tools', NOW())
ON CONFLICT (id) DO NOTHING;

-- Note: Production-specific data such as:
-- - api_keys (contains sensitive keys)
-- - credentials (contains provider credentials)
-- - users (contains user information)
-- - tenants (contains tenant configuration)
-- should be configured separately through secure provisioning process.
