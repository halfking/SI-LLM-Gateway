-- ===========================================================================
-- Object:   idx_models_canonical_strengths
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_models_canonical_strengths; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_models_canonical_strengths ON public.models_canonical USING gin (strengths);


--
