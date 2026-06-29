-- ===========================================================================
-- Object:   prompt_injection_stats_today
-- Type:     VIEW
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: prompt_injection_stats_today; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.prompt_injection_stats_today AS
 SELECT prompt_injection_detections.tenant_id,
    count(*) AS total_detections,
    count(*) FILTER (WHERE (prompt_injection_detections.blocked = true)) AS blocked_count,
    count(*) FILTER (WHERE ((prompt_injection_detections.risk_level = 10) OR (prompt_injection_detections.risk_level = 9))) AS critical_count,
    count(*) FILTER (WHERE ((prompt_injection_detections.risk_level >= 7) AND (prompt_injection_detections.risk_level <= 8))) AS high_count,
    count(*) FILTER (WHERE ((prompt_injection_detections.risk_level >= 4) AND (prompt_injection_detections.risk_level <= 6))) AS medium_count,
    count(*) FILTER (WHERE (prompt_injection_detections.risk_level <= 3)) AS low_count,
    avg(prompt_injection_detections.risk_level) AS avg_score,
    max(prompt_injection_detections.risk_level) AS max_score
   FROM public.prompt_injection_detections
  WHERE (prompt_injection_detections.detected_at >= CURRENT_DATE)
  GROUP BY prompt_injection_detections.tenant_id;


--
