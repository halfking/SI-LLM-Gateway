-- ============================================
-- Indexes for table: tuning_signals
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_tuning_signals_lowq ON public.tuning_signals USING btree (task_type, ts DESC) WHERE ((quality_score < 0.5) AND (classifier = 'heuristic'::text));
CREATE INDEX idx_tuning_signals_session ON public.tuning_signals USING btree (session_id, ts DESC) WHERE (session_id IS NOT NULL);
CREATE INDEX idx_tuning_signals_strategy_task ON public.tuning_signals USING btree (strategy, task_type, ts DESC) WHERE (task_type IS NOT NULL);
CREATE INDEX idx_tuning_signals_strategy_ts ON public.tuning_signals USING btree (strategy, ts DESC);
CREATE INDEX idx_tuning_signals_task_ts ON public.tuning_signals USING btree (task_type, ts DESC);
