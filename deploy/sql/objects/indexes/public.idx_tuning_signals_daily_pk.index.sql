-- ===========================================================================
-- Object:   idx_tuning_signals_daily_pk
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tuning_signals_daily_pk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tuning_signals_daily_pk ON public.tuning_signals_daily USING btree (bucket, task_type, classifier);


--
