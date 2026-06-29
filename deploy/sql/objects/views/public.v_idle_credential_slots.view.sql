-- ===========================================================================
-- Object:   v_idle_credential_slots
-- Type:     VIEW
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: v_idle_credential_slots; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_idle_credential_slots AS
 SELECT model_probe_state.credential_id,
    model_probe_state.raw_model_name,
    model_probe_state.state,
    model_probe_state.consecutive_failures,
    model_probe_state.last_attempt_at,
    (EXTRACT(epoch FROM (now() - model_probe_state.last_attempt_at)))::integer AS idle_seconds
   FROM public.model_probe_state
  WHERE (model_probe_state.state <> 'broken_confirmed'::text);


--
