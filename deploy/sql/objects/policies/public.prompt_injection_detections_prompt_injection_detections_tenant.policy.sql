-- ===========================================================================
-- Object:   prompt_injection_detections prompt_injection_detections_tenant
-- Type:     POLICY
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: prompt_injection_detections prompt_injection_detections_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY prompt_injection_detections_tenant ON public.prompt_injection_detections USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));


--
