-- ===========================================================================
-- Object:   request_logs trg_update_api_key_model_cost
-- Type:     TRIGGER
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs trg_update_api_key_model_cost; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_api_key_model_cost AFTER INSERT ON public.request_logs FOR EACH ROW WHEN ((new.is_auto_request = true)) EXECUTE FUNCTION public.update_api_key_model_cost();


--
