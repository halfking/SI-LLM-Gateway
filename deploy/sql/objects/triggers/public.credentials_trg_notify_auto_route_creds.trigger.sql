-- ===========================================================================
-- Object:   credentials trg_notify_auto_route_creds
-- Type:     TRIGGER
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credentials trg_notify_auto_route_creds; Type: TRIGGER; Schema: public; Owner: -
--
-- v737 audit C2: trigger UPDATE OF must include plan_type so that
-- direct-SQL PATCH credentials SET plan_type = ... fires the LISTEN
-- auto_route_refresh NOTIFY. Without this, fresh DBs bootstrapped
-- from full_schema.sql would silently drop plan_type PATCH
-- invalidation until the 5s candCache TTL expires. See
-- deploy/sql/migrations/063_credentials_plan_type.sql for the
-- idempotent migration that adds plan_type to the live 71 DB.
CREATE TRIGGER trg_notify_auto_route_creds AFTER UPDATE OF status, availability_state, quota_state, circuit_state, concurrency_limit, lifecycle_status, manual_disabled, plan_type ON public.credentials FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.notify_auto_route_refresh();


--
