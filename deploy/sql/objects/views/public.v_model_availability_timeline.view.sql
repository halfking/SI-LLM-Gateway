-- ===========================================================================
-- Object:   v_model_availability_timeline
-- Type:     VIEW
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: v_model_availability_timeline; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_model_availability_timeline AS
 SELECT mpr.raw_model_name,
    mpr.raw_model_name AS outbound_model_name,
    date_trunc('hour'::text, mpr.created_at) AS hour_bucket,
    count(*) AS total_probes,
    count(*) FILTER (WHERE (mpr.status = 'ok'::text)) AS successful_probes,
    count(*) FILTER (WHERE (mpr.status <> 'ok'::text)) AS failed_probes,
    round((((count(*) FILTER (WHERE (mpr.status = 'ok'::text)))::numeric * 100.0) / (count(*))::numeric), 2) AS success_rate,
    avg(mpr.latency_ms) FILTER (WHERE (mpr.status = 'ok'::text)) AS avg_latency_ms,
    count(DISTINCT mpr.credential_id) AS probed_credentials,
    count(DISTINCT mpr.credential_id) FILTER (WHERE (mpr.status = 'ok'::text)) AS successful_credentials,
    count(DISTINCT mpr.credential_id) FILTER (WHERE (mpr.status <> 'ok'::text)) AS failed_credentials
   FROM public.model_probe_runs mpr
  WHERE (mpr.created_at >= (now() - '24:00:00'::interval))
  GROUP BY mpr.raw_model_name, (date_trunc('hour'::text, mpr.created_at))
  ORDER BY mpr.raw_model_name, (date_trunc('hour'::text, mpr.created_at)) DESC;


--
