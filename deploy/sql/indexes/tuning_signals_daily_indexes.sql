-- ============================================
-- Indexes for table: tuning_signals_daily
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE UNIQUE INDEX idx_tuning_signals_daily_pk ON public.tuning_signals_daily USING btree (bucket, task_type, classifier);
CREATE INDEX idx_tuning_signals_daily_task_ts ON public.tuning_signals_daily USING btree (task_type, classifier, bucket DESC);
