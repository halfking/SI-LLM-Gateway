-- ============================================
-- LLM Gateway Database Schema
-- Category: 10-tool
-- Generated: 2026-07-05 17:14:33
-- ============================================

-- ----------------------------------------
-- Table: tool_call_events
-- ----------------------------------------






-- Name: tool_call_events; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.tool_call_events (
    id bigint,
    tool_id character varying(128),
    tenant_id character varying(64),
    request_id character varying(64),
    api_key character varying(64),
    status character varying(16),
    latency_ms integer,
    error_code character varying(64),
    called_at timestamp with time zone
);


-- Name: tool_call_events tenant_isolation_tool_call_events; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_tool_call_events ON public.tool_call_events USING (((tenant_id)::text = public.get_current_tenant()));


-- Name: tool_call_events; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.tool_call_events ENABLE ROW LEVEL SECURITY;


\unrestrict ehXiLTxNzSsltgp9zKPNLVAOh5YdRHNbuYKoLaw2QWdAy2TcbASpF5QX7r2O4kk


-- ----------------------------------------
-- Table: tool_categories
-- ----------------------------------------






-- Name: tool_categories; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.tool_categories (
    id character varying(64) NOT NULL,
    name character varying(128) NOT NULL,
    description text,
    enabled boolean DEFAULT true,
    display_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


-- Name: TABLE tool_categories; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.tool_categories IS 'Phase 2: Tool category definitions for layered loading';


-- Name: idx_tool_categories_order; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_categories_order ON public.tool_categories USING btree (display_order) WHERE (enabled = true);



\unrestrict gjpH1c7aL2r8XRqM9enxUHWqjux1eB0OYIHFhGUx8ftNxzqzYdvCwQHu6fJCfQs


-- ----------------------------------------
-- Table: tool_registry
-- ----------------------------------------






-- Name: tool_registry; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.tool_registry (
    id integer NOT NULL,
    category character varying(64) NOT NULL,
    tool_name character varying(128) NOT NULL,
    tool_definition jsonb NOT NULL,
    enabled boolean DEFAULT true,
    priority integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    tool_id character varying(128) NOT NULL,
    tenant_id character varying(64) DEFAULT 'default'::character varying,
    version integer DEFAULT 1,
    deprecation_date timestamp with time zone,
    min_client_version character varying(32),
    breaking_changes jsonb DEFAULT '[]'::jsonb,
    superseded_by character varying(128)
);


-- Name: TABLE tool_registry; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.tool_registry IS 'Phase 2: Centralized tool definition registry';


-- Name: COLUMN tool_registry.tool_id; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tool_registry.tool_id IS 'Phase 3: Unique tool identifier (category.tool_name)';


-- Name: COLUMN tool_registry.tenant_id; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tool_registry.tenant_id IS 'Phase 3: Tenant isolation (default = global shared)';


-- Name: COLUMN tool_registry.version; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tool_registry.version IS 'Tool version (Phase 3.2: 多版本共存)';


-- Name: COLUMN tool_registry.deprecation_date; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tool_registry.deprecation_date IS 'Deprecated after this date (Phase 3.2: 版本管理)';


-- Name: COLUMN tool_registry.min_client_version; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tool_registry.min_client_version IS 'Minimum client version required (Phase 3.2: 版本管理)';


-- Name: COLUMN tool_registry.breaking_changes; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tool_registry.breaking_changes IS 'List of breaking changes in this version (Phase 3.2: 版本管理)';


-- Name: COLUMN tool_registry.superseded_by; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tool_registry.superseded_by IS 'Newer tool_id that replaces this version (Phase 3.2: 版本管理)';


-- Name: tool_registry_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.tool_registry_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: tool_registry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.tool_registry_id_seq OWNED BY public.tool_registry.id;


-- Name: tool_registry id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_registry ALTER COLUMN id SET DEFAULT nextval('public.tool_registry_id_seq'::regclass);


-- Name: tool_registry tool_registry_tool_name_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_registry
    ADD CONSTRAINT tool_registry_tool_name_key UNIQUE (tool_name);


-- Name: idx_tool_registry_category; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_registry_category ON public.tool_registry USING btree (category) WHERE (enabled = true);


-- Name: idx_tool_registry_deprecation; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_registry_deprecation ON public.tool_registry USING btree (deprecation_date) WHERE (deprecation_date IS NOT NULL);


-- Name: idx_tool_registry_name; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_registry_name ON public.tool_registry USING btree (tool_name) WHERE (enabled = true);


-- Name: idx_tool_registry_tenant_tool; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_registry_tenant_tool ON public.tool_registry USING btree (tenant_id, tool_id, version DESC);


-- Name: idx_tool_registry_unique_version; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX idx_tool_registry_unique_version ON public.tool_registry USING btree (tenant_id, tool_id, version);


-- Name: tool_registry tenant_isolation_tool_registry; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_tool_registry ON public.tool_registry USING ((((tenant_id)::text = public.get_current_tenant()) OR (tenant_id IS NULL) OR ((tenant_id)::text = 'default'::text)));


-- Name: tool_registry; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.tool_registry ENABLE ROW LEVEL SECURITY;


\unrestrict jtAyeuNFutKvV8995NdaG0hj2UDsE0SheyDjRNhNplmahsHJb9ZAQue64UwvhKz


-- ----------------------------------------
-- Table: tool_usage_stats
-- ----------------------------------------





-- Name: tool_usage_stats; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.tool_usage_stats (
    id bigint NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
)
PARTITION BY RANGE (created_at);


-- Name: tool_usage_stats_partitioned_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.tool_usage_stats_partitioned_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: tool_usage_stats_partitioned_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.tool_usage_stats_partitioned_id_seq OWNED BY public.tool_usage_stats.id;


-- Name: tool_usage_stats id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats ALTER COLUMN id SET DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass);


-- Name: tool_usage_stats tool_usage_stats_partitioned_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats
    ADD CONSTRAINT tool_usage_stats_partitioned_pkey PRIMARY KEY (id, created_at);


-- Name: tool_usage_stats tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats
    ADD CONSTRAINT tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key UNIQUE (tool_id, tenant_id, usage_date, created_at);


-- Name: idx_tool_stats_part_created; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_stats_part_created ON ONLY public.tool_usage_stats USING btree (created_at);


-- Name: idx_tool_stats_part_date; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_stats_part_date ON ONLY public.tool_usage_stats USING btree (usage_date);


-- Name: idx_tool_stats_part_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_stats_part_tenant ON ONLY public.tool_usage_stats USING btree (tenant_id, usage_date);


-- Name: idx_tool_stats_part_tool; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_stats_part_tool ON ONLY public.tool_usage_stats USING btree (tool_id, usage_date);


-- Name: tool_usage_stats tenant_isolation_tool_usage_stats; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_tool_usage_stats ON public.tool_usage_stats USING (((tenant_id)::text = public.get_current_tenant()));


-- Name: tool_usage_stats; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.tool_usage_stats ENABLE ROW LEVEL SECURITY;


\unrestrict EbazPAoD6Qv3mRo9Q0AAPmaJ3let04qYskcXMt0w8fJEqUpPpLF6ifFJshLjZv2


-- ----------------------------------------
-- Table: tool_usage_stats_2026_06
-- ----------------------------------------






-- Name: tool_usage_stats_2026_06; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.tool_usage_stats_2026_06 (
    id bigint DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass) NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);


-- Name: tool_usage_stats_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats ATTACH PARTITION public.tool_usage_stats_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


-- Name: tool_usage_stats_2026_06 tool_usage_stats_2026_06_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats_2026_06
    ADD CONSTRAINT tool_usage_stats_2026_06_pkey PRIMARY KEY (id, created_at);


-- Name: tool_usage_stats_2026_06 tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats_2026_06
    ADD CONSTRAINT tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key UNIQUE (tool_id, tenant_id, usage_date, created_at);


-- Name: tool_usage_stats_2026_06_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_06_created_at_idx ON public.tool_usage_stats_2026_06 USING btree (created_at);


-- Name: tool_usage_stats_2026_06_tenant_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_06_tenant_id_usage_date_idx ON public.tool_usage_stats_2026_06 USING btree (tenant_id, usage_date);


-- Name: tool_usage_stats_2026_06_tool_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_06_tool_id_usage_date_idx ON public.tool_usage_stats_2026_06 USING btree (tool_id, usage_date);


-- Name: tool_usage_stats_2026_06_usage_date_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_06_usage_date_idx ON public.tool_usage_stats_2026_06 USING btree (usage_date);


-- Name: tool_usage_stats_2026_06_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_created ATTACH PARTITION public.tool_usage_stats_2026_06_created_at_idx;


-- Name: tool_usage_stats_2026_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.tool_usage_stats_partitioned_pkey ATTACH PARTITION public.tool_usage_stats_2026_06_pkey;


-- Name: tool_usage_stats_2026_06_tenant_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_tenant ATTACH PARTITION public.tool_usage_stats_2026_06_tenant_id_usage_date_idx;


-- Name: tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key ATTACH PARTITION public.tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key;


-- Name: tool_usage_stats_2026_06_tool_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_tool ATTACH PARTITION public.tool_usage_stats_2026_06_tool_id_usage_date_idx;


-- Name: tool_usage_stats_2026_06_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_date ATTACH PARTITION public.tool_usage_stats_2026_06_usage_date_idx;



\unrestrict bPJrnk3pYuzobybaDdUMS4XQ8XlZde6oLO9TQqZ5D3mQhc5BFwbip00INCjBwMA


-- ----------------------------------------
-- Table: tool_usage_stats_2026_07
-- ----------------------------------------






-- Name: tool_usage_stats_2026_07; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.tool_usage_stats_2026_07 (
    id bigint DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass) NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);


-- Name: tool_usage_stats_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats ATTACH PARTITION public.tool_usage_stats_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


-- Name: tool_usage_stats_2026_07 tool_usage_stats_2026_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats_2026_07
    ADD CONSTRAINT tool_usage_stats_2026_07_pkey PRIMARY KEY (id, created_at);


-- Name: tool_usage_stats_2026_07 tool_usage_stats_2026_07_tool_id_tenant_id_usage_date_creat_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats_2026_07
    ADD CONSTRAINT tool_usage_stats_2026_07_tool_id_tenant_id_usage_date_creat_key UNIQUE (tool_id, tenant_id, usage_date, created_at);


-- Name: tool_usage_stats_2026_07_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_07_created_at_idx ON public.tool_usage_stats_2026_07 USING btree (created_at);


-- Name: tool_usage_stats_2026_07_tenant_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_07_tenant_id_usage_date_idx ON public.tool_usage_stats_2026_07 USING btree (tenant_id, usage_date);


-- Name: tool_usage_stats_2026_07_tool_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_07_tool_id_usage_date_idx ON public.tool_usage_stats_2026_07 USING btree (tool_id, usage_date);


-- Name: tool_usage_stats_2026_07_usage_date_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_07_usage_date_idx ON public.tool_usage_stats_2026_07 USING btree (usage_date);


-- Name: tool_usage_stats_2026_07_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_created ATTACH PARTITION public.tool_usage_stats_2026_07_created_at_idx;


-- Name: tool_usage_stats_2026_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.tool_usage_stats_partitioned_pkey ATTACH PARTITION public.tool_usage_stats_2026_07_pkey;


-- Name: tool_usage_stats_2026_07_tenant_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_tenant ATTACH PARTITION public.tool_usage_stats_2026_07_tenant_id_usage_date_idx;


-- Name: tool_usage_stats_2026_07_tool_id_tenant_id_usage_date_creat_key; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key ATTACH PARTITION public.tool_usage_stats_2026_07_tool_id_tenant_id_usage_date_creat_key;


-- Name: tool_usage_stats_2026_07_tool_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_tool ATTACH PARTITION public.tool_usage_stats_2026_07_tool_id_usage_date_idx;


-- Name: tool_usage_stats_2026_07_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_date ATTACH PARTITION public.tool_usage_stats_2026_07_usage_date_idx;



\unrestrict T5xHTJGpqR0WJEgrENaEZWv5FyEgHJZX6wY6XTdguzKW14IQ0WmUrEJ6RcjWqNW


-- ----------------------------------------
-- Table: tool_usage_stats_2026_08
-- ----------------------------------------






-- Name: tool_usage_stats_2026_08; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.tool_usage_stats_2026_08 (
    id bigint DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass) NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);


-- Name: tool_usage_stats_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats ATTACH PARTITION public.tool_usage_stats_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


-- Name: tool_usage_stats_2026_08 tool_usage_stats_2026_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats_2026_08
    ADD CONSTRAINT tool_usage_stats_2026_08_pkey PRIMARY KEY (id, created_at);


-- Name: tool_usage_stats_2026_08 tool_usage_stats_2026_08_tool_id_tenant_id_usage_date_creat_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats_2026_08
    ADD CONSTRAINT tool_usage_stats_2026_08_tool_id_tenant_id_usage_date_creat_key UNIQUE (tool_id, tenant_id, usage_date, created_at);


-- Name: tool_usage_stats_2026_08_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_08_created_at_idx ON public.tool_usage_stats_2026_08 USING btree (created_at);


-- Name: tool_usage_stats_2026_08_tenant_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_08_tenant_id_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (tenant_id, usage_date);


-- Name: tool_usage_stats_2026_08_tool_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_08_tool_id_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (tool_id, usage_date);


-- Name: tool_usage_stats_2026_08_usage_date_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX tool_usage_stats_2026_08_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (usage_date);


-- Name: tool_usage_stats_2026_08_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_created ATTACH PARTITION public.tool_usage_stats_2026_08_created_at_idx;


-- Name: tool_usage_stats_2026_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.tool_usage_stats_partitioned_pkey ATTACH PARTITION public.tool_usage_stats_2026_08_pkey;


-- Name: tool_usage_stats_2026_08_tenant_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_tenant ATTACH PARTITION public.tool_usage_stats_2026_08_tenant_id_usage_date_idx;


-- Name: tool_usage_stats_2026_08_tool_id_tenant_id_usage_date_creat_key; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key ATTACH PARTITION public.tool_usage_stats_2026_08_tool_id_tenant_id_usage_date_creat_key;


-- Name: tool_usage_stats_2026_08_tool_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_tool ATTACH PARTITION public.tool_usage_stats_2026_08_tool_id_usage_date_idx;


-- Name: tool_usage_stats_2026_08_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_tool_stats_part_date ATTACH PARTITION public.tool_usage_stats_2026_08_usage_date_idx;



\unrestrict 7JY0M8Av7eZ7Nf1yByURebXfO9rTJ1z1xfbeY4pZkQ5QZFLAk8kcSq8bJtDrFfi


-- ----------------------------------------
-- Table: tool_usage_stats_old
-- ----------------------------------------






-- Name: tool_usage_stats_old; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.tool_usage_stats_old (
    id bigint NOT NULL,
    tool_id character varying(128) NOT NULL,
    tenant_id character varying(64) DEFAULT 'default'::character varying NOT NULL,
    usage_date date DEFAULT CURRENT_DATE NOT NULL,
    call_count bigint DEFAULT 0 NOT NULL,
    success_count bigint DEFAULT 0 NOT NULL,
    error_count bigint DEFAULT 0 NOT NULL,
    avg_latency_ms integer DEFAULT 0,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.tool_usage_stats_old FORCE ROW LEVEL SECURITY;


-- Name: TABLE tool_usage_stats_old; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.tool_usage_stats_old IS 'Tool usage statistics (Phase 3.3: 使用统计)';


-- Name: COLUMN tool_usage_stats_old.call_count; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tool_usage_stats_old.call_count IS 'Total call count for this tool on this day';


-- Name: COLUMN tool_usage_stats_old.success_count; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tool_usage_stats_old.success_count IS 'Successful call count';


-- Name: COLUMN tool_usage_stats_old.error_count; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tool_usage_stats_old.error_count IS 'Failed call count';


-- Name: tool_usage_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.tool_usage_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: tool_usage_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.tool_usage_stats_id_seq OWNED BY public.tool_usage_stats_old.id;


-- Name: tool_usage_stats_old id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats_old ALTER COLUMN id SET DEFAULT nextval('public.tool_usage_stats_id_seq'::regclass);


-- Name: tool_usage_stats_old uk_tool_usage_stats; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tool_usage_stats_old
    ADD CONSTRAINT uk_tool_usage_stats UNIQUE (tool_id, tenant_id, usage_date);


-- Name: idx_tool_usage_stats_date; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_usage_stats_date ON public.tool_usage_stats_old USING btree (usage_date DESC);


-- Name: idx_tool_usage_stats_tenant_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_usage_stats_tenant_id ON public.tool_usage_stats_old USING btree (tenant_id);


-- Name: idx_tool_usage_stats_tool_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_usage_stats_tool_id ON public.tool_usage_stats_old USING btree (tool_id);


-- Name: idx_tool_usage_stats_tool_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tool_usage_stats_tool_tenant ON public.tool_usage_stats_old USING btree (tool_id, tenant_id, usage_date DESC);


-- Name: tool_usage_stats_old tenant_isolation_tool_usage_stats; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_tool_usage_stats ON public.tool_usage_stats_old USING (((tenant_id)::text = public.get_current_tenant()));


-- Name: tool_usage_stats_old; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.tool_usage_stats_old ENABLE ROW LEVEL SECURITY;


\unrestrict fvZUwAA1eXYZ7o6UvVzJzcOrtIcXTs4vKnYQSFVkt9XuSvCyzk6IZhGIbylY9tk


