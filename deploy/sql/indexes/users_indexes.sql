-- ============================================
-- Indexes for table: users
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_users_tenant ON public.users USING btree (tenant_id);
CREATE INDEX idx_users_username ON public.users USING btree (username);
