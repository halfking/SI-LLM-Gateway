-- ===========================================================================
-- Object:   v_format_anomaly_summary
-- Type:     VIEW
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: v_format_anomaly_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_format_anomaly_summary AS
 SELECT date_trunc('hour'::text, response_format_anomalies.detected_at) AS hour,
    response_format_anomalies.provider_code,
    response_format_anomalies.client_model,
    response_format_anomalies.anomaly_type,
    response_format_anomalies.severity,
    count(*) AS anomaly_count,
    count(DISTINCT response_format_anomalies.request_id) AS affected_requests,
    avg(response_format_anomalies.content_size_bytes) AS avg_content_size,
    avg(response_format_anomalies.expected_tokens) AS avg_expected_tokens,
    avg(response_format_anomalies.actual_tokens) AS avg_actual_tokens,
    count(*) FILTER (WHERE response_format_anomalies.resolved) AS resolved_count
   FROM public.response_format_anomalies
  WHERE (response_format_anomalies.detected_at > (now() - '7 days'::interval))
  GROUP BY (date_trunc('hour'::text, response_format_anomalies.detected_at)), response_format_anomalies.provider_code, response_format_anomalies.client_model, response_format_anomalies.anomaly_type, response_format_anomalies.severity;


--
