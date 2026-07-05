-- ============================================
-- Indexes for table: goal_sessions
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_goal_sessions_session ON public.goal_sessions USING btree (session_id);
CREATE INDEX idx_goal_sessions_state ON public.goal_sessions USING btree (state, last_activity_at);
CREATE INDEX idx_goal_sessions_tenant ON public.goal_sessions USING btree (tenant_id, state);
