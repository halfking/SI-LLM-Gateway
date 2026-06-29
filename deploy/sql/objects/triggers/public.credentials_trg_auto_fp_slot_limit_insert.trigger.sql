-- ===========================================================================
-- Object:   credentials trg_auto_fp_slot_limit_insert
-- Type:     TRIGGER
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credentials trg_auto_fp_slot_limit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_auto_fp_slot_limit_insert BEFORE INSERT ON public.credentials FOR EACH ROW EXECUTE FUNCTION public.auto_set_fp_slot_limit();


--
