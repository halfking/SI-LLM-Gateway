-- ===========================================================================
-- Object:   routing_overrides routing_overrides_audit_trg
-- Type:     TRIGGER
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: routing_overrides routing_overrides_audit_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER routing_overrides_audit_trg AFTER INSERT OR DELETE OR UPDATE ON public.routing_overrides FOR EACH ROW EXECUTE FUNCTION public.routing_overrides_audit_fn();


--
