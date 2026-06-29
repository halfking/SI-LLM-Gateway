-- ===========================================================================
-- Object:   idx_tuning_signals_strategy_task
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tuning_signals_strategy_task; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_signals_strategy_task ON public.tuning_signals USING btree (strategy, task_type, ts DESC) WHERE (task_type IS NOT NULL);


--
