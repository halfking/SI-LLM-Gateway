-- ===========================================================================
-- Object:   provider_settings trigger_provider_settings_updated_at
-- Type:     TRIGGER
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: provider_settings trigger_provider_settings_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_provider_settings_updated_at BEFORE UPDATE ON public.provider_settings FOR EACH ROW EXECUTE FUNCTION public.update_provider_settings_updated_at();


--
