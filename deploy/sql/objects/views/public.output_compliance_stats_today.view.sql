-- ===========================================================================
-- Object:   output_compliance_stats_today
-- Type:     VIEW
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: output_compliance_stats_today; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.output_compliance_stats_today AS
 SELECT output_compliance_audit.tenant_id,
    count(*) AS total_issues,
    count(*) FILTER (WHERE (output_compliance_audit.redacted = true)) AS redacted_count,
    count(*) FILTER (WHERE (output_compliance_audit.blocked = true)) AS blocked_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'pii'::text)) AS pii_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'toxic'::text)) AS toxic_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'bias'::text)) AS bias_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'hallucination'::text)) AS hallucination_count,
    avg(output_compliance_audit.severity) AS avg_severity,
    max(output_compliance_audit.severity) AS max_severity
   FROM public.output_compliance_audit
  WHERE (output_compliance_audit.detected_at >= CURRENT_DATE)
  GROUP BY output_compliance_audit.tenant_id;


--
