-- ===========================================================================
-- Object:   tenant_model_policies_active
-- Type:     VIEW
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tenant_model_policies_active; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tenant_model_policies_active AS
 SELECT tenant_model_policies.id,
    tenant_model_policies.tenant_id,
    tenant_model_policies.canonical_name,
    tenant_model_policies.reason,
    tenant_model_policies.created_by,
    tenant_model_policies.created_at,
    tenant_model_policies.updated_at
   FROM public.tenant_model_policies
  WHERE (tenant_model_policies.deleted_at IS NULL);


--
