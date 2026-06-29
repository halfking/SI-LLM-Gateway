-- ===========================================================================
-- Object:   idx_tuning_signals_strategy_ts
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tuning_signals_strategy_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_signals_strategy_ts ON public.tuning_signals USING btree (strategy, ts DESC);


--
