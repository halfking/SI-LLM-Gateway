-- ===========================================================================
-- Object:   ops_model_offers_backup_backup_id_seq
-- Type:     SEQUENCE
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: ops_model_offers_backup_backup_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ops_model_offers_backup_backup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ops_model_offers_backup_backup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ops_model_offers_backup_backup_id_seq OWNED BY public.ops_model_offers_backup.backup_id;


--
