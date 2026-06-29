-- ===========================================================================
-- Object:   session_stats_today
-- Type:     VIEW
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: session_stats_today; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.session_stats_today AS
 SELECT session_summaries.tenant_id,
    count(*) AS session_count,
    count(*) FILTER (WHERE (session_summaries.last_request_at > (now() - '01:00:00'::interval))) AS active_sessions,
    sum(session_summaries.request_count) AS total_requests,
    sum(session_summaries.total_cost_usd) AS total_cost,
    avg(session_summaries.total_cost_usd) AS avg_cost_per_session,
    avg(session_summaries.total_tokens) AS avg_tokens_per_session,
    avg(session_summaries.avg_latency_ms) AS avg_latency,
    (((count(*) FILTER (WHERE ((session_summaries.compliance_status)::text = 'compliant'::text)))::numeric * 100.0) / (NULLIF(count(*), 0))::numeric) AS compliance_rate,
    (((count(*) FILTER (WHERE (session_summaries.quality_score >= 8)))::numeric * 100.0) / (NULLIF(count(*) FILTER (WHERE (session_summaries.quality_score IS NOT NULL)), 0))::numeric) AS high_quality_rate
   FROM public.session_summaries
  WHERE (session_summaries.first_request_at >= CURRENT_DATE)
  GROUP BY session_summaries.tenant_id;


--
