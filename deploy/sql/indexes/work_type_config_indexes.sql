-- ============================================
-- Indexes for table: work_type_config
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_work_type_config_category ON public.work_type_config USING btree (category, sort_order);
CREATE INDEX idx_work_type_config_l1 ON public.work_type_config USING btree (l1_task_type);
