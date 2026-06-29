-- ===========================================================================
-- Object:   credentials trg_notify_auto_route_creds
-- Type:     TRIGGER
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credentials trg_notify_auto_route_creds; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_auto_route_creds AFTER UPDATE OF status, availability_state, quota_state, circuit_state, concurrency_limit, lifecycle_status, manual_disabled ON public.credentials FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.notify_auto_route_refresh();


--
