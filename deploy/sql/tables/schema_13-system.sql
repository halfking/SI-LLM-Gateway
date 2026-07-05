-- ============================================
-- LLM Gateway Database Schema
-- Category: 13-system
-- Generated: 2026-07-05 17:14:34
-- ============================================

-- ----------------------------------------
-- Table: background_tasks
-- ----------------------------------------






-- Name: background_tasks; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.background_tasks (
    id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    task_type text NOT NULL,
    provider_id bigint,
    credential_id bigint,
    status text DEFAULT 'running'::text NOT NULL,
    request_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    result_json jsonb,
    error text,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone
);


-- Name: background_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.background_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: background_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.background_tasks_id_seq OWNED BY public.background_tasks.id;


-- Name: background_tasks id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.background_tasks ALTER COLUMN id SET DEFAULT nextval('public.background_tasks_id_seq'::regclass);


-- Name: background_tasks background_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.background_tasks
    ADD CONSTRAINT background_tasks_pkey PRIMARY KEY (id);



\unrestrict tjVaNhtUiJlgDz0nxX3ExHLbnpwhPM8NrZx9a4uji3vN76bFsqzpZabF30w7o5L


-- ----------------------------------------
-- Table: background_tasks_duplicates
-- ----------------------------------------






-- Name: background_tasks_duplicates; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.background_tasks_duplicates (
    id bigint NOT NULL,
    tenant_id text NOT NULL,
    task_type text NOT NULL,
    provider_id bigint,
    credential_id bigint,
    status text NOT NULL,
    request_json jsonb NOT NULL,
    result_json jsonb,
    error text,
    started_at timestamp with time zone NOT NULL,
    finished_at timestamp with time zone,
    removed_at timestamp with time zone DEFAULT now()
);



\unrestrict N4dOKA5ICKMyHKDe4RUgSaXVN4YoYkK5Pu2IieN4fSA2NsLPDK35ugswCHzySbE


-- ----------------------------------------
-- Table: schema_migrations
-- ----------------------------------------






-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.schema_migrations (
    version text NOT NULL,
    description text,
    applied_at timestamp with time zone DEFAULT now()
);



\unrestrict b5FPgQ5V2zSb6fQzMF0Yg1TCKtDUud91xcyWtFq70AcNEc1KGWFEBukNVZkk9Ot


