-- ===========================================================================
-- Object:   credential_model_bindings cmb_protect_manual_disable
-- Type:     TRIGGER
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_model_bindings cmb_protect_manual_disable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cmb_protect_manual_disable BEFORE UPDATE ON public.credential_model_bindings FOR EACH ROW EXECUTE FUNCTION public.trg_cmb_protect_manual_disable();


--
