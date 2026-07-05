-- ============================================
-- LLM Gateway Database Schema
-- Category: 07-billing
-- Generated: 2026-07-05 17:14:22
-- ============================================

-- ----------------------------------------
-- Table: credit_ledger
-- ----------------------------------------





-- Name: credit_ledger; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credit_ledger (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
)
PARTITION BY RANGE (created_at);


-- Name: credit_ledger_partitioned_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.credit_ledger_partitioned_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: credit_ledger_partitioned_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.credit_ledger_partitioned_id_seq OWNED BY public.credit_ledger.id;


-- Name: credit_ledger id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.credit_ledger ALTER COLUMN id SET DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass);


-- Name: credit_ledger credit_ledger_partitioned_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credit_ledger
    ADD CONSTRAINT credit_ledger_partitioned_pkey PRIMARY KEY (id, created_at);


-- Name: idx_credit_ledger_part_created; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_credit_ledger_part_created ON ONLY public.credit_ledger USING btree (created_at);


-- Name: idx_credit_ledger_part_ref; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_credit_ledger_part_ref ON ONLY public.credit_ledger USING btree (ref_type, ref_id);


-- Name: idx_credit_ledger_part_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_credit_ledger_part_tenant ON ONLY public.credit_ledger USING btree (tenant_id, created_at);



\unrestrict hUKj1xj80CWltJtLt9efIU0NspRcvegsPX0bZ404IY0AQkif5pXvaxSyzBWdrwG


-- ----------------------------------------
-- Table: credit_ledger_2026_06
-- ----------------------------------------






-- Name: credit_ledger_2026_06; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credit_ledger_2026_06 (
    id bigint DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass) NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
);


-- Name: credit_ledger_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.credit_ledger ATTACH PARTITION public.credit_ledger_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


-- Name: credit_ledger_2026_06 credit_ledger_2026_06_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credit_ledger_2026_06
    ADD CONSTRAINT credit_ledger_2026_06_pkey PRIMARY KEY (id, created_at);


-- Name: credit_ledger_2026_06_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credit_ledger_2026_06_created_at_idx ON public.credit_ledger_2026_06 USING btree (created_at);


-- Name: credit_ledger_2026_06_ref_type_ref_id_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credit_ledger_2026_06_ref_type_ref_id_idx ON public.credit_ledger_2026_06 USING btree (ref_type, ref_id);


-- Name: credit_ledger_2026_06_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credit_ledger_2026_06_tenant_id_created_at_idx ON public.credit_ledger_2026_06 USING btree (tenant_id, created_at);


-- Name: credit_ledger_2026_06_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_credit_ledger_part_created ATTACH PARTITION public.credit_ledger_2026_06_created_at_idx;


-- Name: credit_ledger_2026_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.credit_ledger_partitioned_pkey ATTACH PARTITION public.credit_ledger_2026_06_pkey;


-- Name: credit_ledger_2026_06_ref_type_ref_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_credit_ledger_part_ref ATTACH PARTITION public.credit_ledger_2026_06_ref_type_ref_id_idx;


-- Name: credit_ledger_2026_06_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_credit_ledger_part_tenant ATTACH PARTITION public.credit_ledger_2026_06_tenant_id_created_at_idx;



\unrestrict qcjOw4XdgvZXnyv1LBBWO0uvXVn0rHtKYfx1Q1SmOtovYqK342hZYiqkdBpPDbS


-- ----------------------------------------
-- Table: credit_ledger_2026_07
-- ----------------------------------------






-- Name: credit_ledger_2026_07; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credit_ledger_2026_07 (
    id bigint DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass) NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
);


-- Name: credit_ledger_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.credit_ledger ATTACH PARTITION public.credit_ledger_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


-- Name: credit_ledger_2026_07 credit_ledger_2026_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credit_ledger_2026_07
    ADD CONSTRAINT credit_ledger_2026_07_pkey PRIMARY KEY (id, created_at);


-- Name: credit_ledger_2026_07_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credit_ledger_2026_07_created_at_idx ON public.credit_ledger_2026_07 USING btree (created_at);


-- Name: credit_ledger_2026_07_ref_type_ref_id_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credit_ledger_2026_07_ref_type_ref_id_idx ON public.credit_ledger_2026_07 USING btree (ref_type, ref_id);


-- Name: credit_ledger_2026_07_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credit_ledger_2026_07_tenant_id_created_at_idx ON public.credit_ledger_2026_07 USING btree (tenant_id, created_at);


-- Name: credit_ledger_2026_07_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_credit_ledger_part_created ATTACH PARTITION public.credit_ledger_2026_07_created_at_idx;


-- Name: credit_ledger_2026_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.credit_ledger_partitioned_pkey ATTACH PARTITION public.credit_ledger_2026_07_pkey;


-- Name: credit_ledger_2026_07_ref_type_ref_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_credit_ledger_part_ref ATTACH PARTITION public.credit_ledger_2026_07_ref_type_ref_id_idx;


-- Name: credit_ledger_2026_07_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_credit_ledger_part_tenant ATTACH PARTITION public.credit_ledger_2026_07_tenant_id_created_at_idx;



\unrestrict xh2YV8jBmOsW7tzku0snDMXvBZuM2qCqk4GpVFesKsE5FPgKVbhRuGt9ZbyK89F


-- ----------------------------------------
-- Table: credit_ledger_2026_08
-- ----------------------------------------






-- Name: credit_ledger_2026_08; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credit_ledger_2026_08 (
    id bigint DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass) NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
);


-- Name: credit_ledger_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.credit_ledger ATTACH PARTITION public.credit_ledger_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


-- Name: credit_ledger_2026_08 credit_ledger_2026_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credit_ledger_2026_08
    ADD CONSTRAINT credit_ledger_2026_08_pkey PRIMARY KEY (id, created_at);


-- Name: credit_ledger_2026_08_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credit_ledger_2026_08_created_at_idx ON public.credit_ledger_2026_08 USING btree (created_at);


-- Name: credit_ledger_2026_08_ref_type_ref_id_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credit_ledger_2026_08_ref_type_ref_id_idx ON public.credit_ledger_2026_08 USING btree (ref_type, ref_id);


-- Name: credit_ledger_2026_08_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credit_ledger_2026_08_tenant_id_created_at_idx ON public.credit_ledger_2026_08 USING btree (tenant_id, created_at);


-- Name: credit_ledger_2026_08_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_credit_ledger_part_created ATTACH PARTITION public.credit_ledger_2026_08_created_at_idx;


-- Name: credit_ledger_2026_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.credit_ledger_partitioned_pkey ATTACH PARTITION public.credit_ledger_2026_08_pkey;


-- Name: credit_ledger_2026_08_ref_type_ref_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_credit_ledger_part_ref ATTACH PARTITION public.credit_ledger_2026_08_ref_type_ref_id_idx;


-- Name: credit_ledger_2026_08_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_credit_ledger_part_tenant ATTACH PARTITION public.credit_ledger_2026_08_tenant_id_created_at_idx;



\unrestrict ajPr4ExkPQL2BddbWOfoULDf4aMhlyLMJ5h3Fxh2myYG8kK4x5BqkHfJXcbhJLy


-- ----------------------------------------
-- Table: credit_ledger_old
-- ----------------------------------------






-- Name: credit_ledger_old; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credit_ledger_old (
    id bigint NOT NULL,
    tenant_id character varying(64) NOT NULL,
    entry_type character varying(32) NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying(32),
    ref_id character varying(128),
    note text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying(32),
    CONSTRAINT credit_ledger_entry_type_check CHECK (((entry_type)::text = ANY (ARRAY[('consume'::character varying)::text, ('topup'::character varying)::text, ('subscribe'::character varying)::text, ('adjust'::character varying)::text, ('refund'::character varying)::text])))
);


-- Name: credit_ledger_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.credit_ledger_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: credit_ledger_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.credit_ledger_id_seq OWNED BY public.credit_ledger_old.id;


-- Name: credit_ledger_old id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.credit_ledger_old ALTER COLUMN id SET DEFAULT nextval('public.credit_ledger_id_seq'::regclass);


-- Name: idx_credit_ledger_tenant_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_credit_ledger_tenant_ts ON public.credit_ledger_old USING btree (tenant_id, created_at DESC);


-- Name: credit_ledger_old; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.credit_ledger_old ENABLE ROW LEVEL SECURITY;

-- Name: credit_ledger_old tenant_isolation_credit_ledger; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_credit_ledger ON public.credit_ledger_old USING (((tenant_id)::text = public.get_current_tenant()));



\unrestrict T5XBhxzE5ONTVPtJ85cZGB4Q8wdf5dHm1TiOWKzRu0EOc36CZ0dizvz9sMGciwh


-- ----------------------------------------
-- Table: usage_ledger
-- ----------------------------------------





-- Name: usage_ledger; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.usage_ledger (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
)
PARTITION BY RANGE (ts);


-- Name: usage_ledger usage_ledger_partitioned_request_id_ts_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.usage_ledger
    ADD CONSTRAINT usage_ledger_partitioned_request_id_ts_key UNIQUE (request_id, ts);


-- Name: idx_usage_ledger_part_request_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_usage_ledger_part_request_id ON ONLY public.usage_ledger USING btree (request_id);


-- Name: idx_usage_ledger_part_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_usage_ledger_part_tenant ON ONLY public.usage_ledger USING btree (tenant_id, ts);


-- Name: idx_usage_ledger_part_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_usage_ledger_part_ts ON ONLY public.usage_ledger USING btree (ts);



\unrestrict GQetb8VbrnsSub7USHjgXC7fXXvxZDSt3rYnXpqk1R4g1H0CB6JUVM2SjNy9jmS


-- ----------------------------------------
-- Table: usage_ledger_2026_06
-- ----------------------------------------






-- Name: usage_ledger_2026_06; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.usage_ledger_2026_06 (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);


-- Name: usage_ledger_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.usage_ledger ATTACH PARTITION public.usage_ledger_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


-- Name: usage_ledger_2026_06 usage_ledger_2026_06_col_request_id_ts_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.usage_ledger_2026_06
    ADD CONSTRAINT usage_ledger_2026_06_col_request_id_ts_key UNIQUE (request_id, ts);


-- Name: usage_ledger_2026_06_col_request_id_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_06_col_request_id_idx ON public.usage_ledger_2026_06 USING btree (request_id);


-- Name: usage_ledger_2026_06_col_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_06_col_tenant_id_ts_idx ON public.usage_ledger_2026_06 USING btree (tenant_id, ts);


-- Name: usage_ledger_2026_06_col_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_06_col_ts_idx ON public.usage_ledger_2026_06 USING btree (ts);


-- Name: usage_ledger_2026_06_col_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_usage_ledger_part_request_id ATTACH PARTITION public.usage_ledger_2026_06_col_request_id_idx;


-- Name: usage_ledger_2026_06_col_request_id_ts_key; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.usage_ledger_partitioned_request_id_ts_key ATTACH PARTITION public.usage_ledger_2026_06_col_request_id_ts_key;


-- Name: usage_ledger_2026_06_col_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_usage_ledger_part_tenant ATTACH PARTITION public.usage_ledger_2026_06_col_tenant_id_ts_idx;


-- Name: usage_ledger_2026_06_col_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_usage_ledger_part_ts ATTACH PARTITION public.usage_ledger_2026_06_col_ts_idx;



\unrestrict o9kWgJeo8dU8fbaQhXGhezsLaZBenQJa2GcCewi5E7jxEjSOKvEOHokdZQ2cBTU


-- ----------------------------------------
-- Table: usage_ledger_2026_07
-- ----------------------------------------






-- Name: usage_ledger_2026_07; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.usage_ledger_2026_07 (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);


-- Name: usage_ledger_2026_07 usage_ledger_2026_07_request_id_ts_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.usage_ledger_2026_07
    ADD CONSTRAINT usage_ledger_2026_07_request_id_ts_key UNIQUE (request_id, ts);


-- Name: usage_ledger_2026_07_request_id_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_07_request_id_idx ON public.usage_ledger_2026_07 USING btree (request_id);


-- Name: usage_ledger_2026_07_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_07_tenant_id_ts_idx ON public.usage_ledger_2026_07 USING btree (tenant_id, ts);


-- Name: usage_ledger_2026_07_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_07_ts_idx ON public.usage_ledger_2026_07 USING btree (ts);



\unrestrict 3KUiEyyC20oMhWvatgOx62p40grHxFQMVImwoPasaF4zvr8fmKfrQC1pu4bmrYY


-- ----------------------------------------
-- Table: usage_ledger_2026_07_columnar_backup
-- ----------------------------------------






-- Name: usage_ledger_2026_07_columnar_backup; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.usage_ledger_2026_07_columnar_backup (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);


-- Name: usage_ledger_2026_07_columnar_backup usage_ledger_2026_07_col_request_id_ts_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.usage_ledger_2026_07_columnar_backup
    ADD CONSTRAINT usage_ledger_2026_07_col_request_id_ts_key UNIQUE (request_id, ts);


-- Name: usage_ledger_2026_07_col_request_id_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_07_col_request_id_idx ON public.usage_ledger_2026_07_columnar_backup USING btree (request_id);


-- Name: usage_ledger_2026_07_col_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_07_col_tenant_id_ts_idx ON public.usage_ledger_2026_07_columnar_backup USING btree (tenant_id, ts);


-- Name: usage_ledger_2026_07_col_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_07_col_ts_idx ON public.usage_ledger_2026_07_columnar_backup USING btree (ts);



\unrestrict FyXX718BA6lSpu29Sujfu3H2B6ZWgQzPF8KkX3QJlKW87tRc3FZC7VZfhcB5zjL


-- ----------------------------------------
-- Table: usage_ledger_2026_08
-- ----------------------------------------






-- Name: usage_ledger_2026_08; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.usage_ledger_2026_08 (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);


-- Name: usage_ledger_2026_08 usage_ledger_2026_08_heap_request_id_ts_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.usage_ledger_2026_08
    ADD CONSTRAINT usage_ledger_2026_08_heap_request_id_ts_key UNIQUE (request_id, ts);


-- Name: usage_ledger_2026_08_heap_request_id_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_08_heap_request_id_idx ON public.usage_ledger_2026_08 USING btree (request_id);


-- Name: usage_ledger_2026_08_heap_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_08_heap_tenant_id_ts_idx ON public.usage_ledger_2026_08 USING btree (tenant_id, ts);


-- Name: usage_ledger_2026_08_heap_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_2026_08_heap_ts_idx ON public.usage_ledger_2026_08 USING btree (ts);



\unrestrict IbJ6jtMqUnPOTCyHPm7zEkhYq5IWe97ZzUf8oGfmUZ75iVf3c6U1PIMeLdmpOEU


-- ----------------------------------------
-- Table: usage_ledger_default
-- ----------------------------------------






-- Name: usage_ledger_default; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.usage_ledger_default (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);


-- Name: usage_ledger_default; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.usage_ledger ATTACH PARTITION public.usage_ledger_default DEFAULT;


-- Name: usage_ledger_default usage_ledger_default_request_id_ts_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.usage_ledger_default
    ADD CONSTRAINT usage_ledger_default_request_id_ts_key UNIQUE (request_id, ts);


-- Name: usage_ledger_default_request_id_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_default_request_id_idx ON public.usage_ledger_default USING btree (request_id);


-- Name: usage_ledger_default_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_default_tenant_id_ts_idx ON public.usage_ledger_default USING btree (tenant_id, ts);


-- Name: usage_ledger_default_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX usage_ledger_default_ts_idx ON public.usage_ledger_default USING btree (ts);


-- Name: usage_ledger_default_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_usage_ledger_part_request_id ATTACH PARTITION public.usage_ledger_default_request_id_idx;


-- Name: usage_ledger_default_request_id_ts_key; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.usage_ledger_partitioned_request_id_ts_key ATTACH PARTITION public.usage_ledger_default_request_id_ts_key;


-- Name: usage_ledger_default_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_usage_ledger_part_tenant ATTACH PARTITION public.usage_ledger_default_tenant_id_ts_idx;


-- Name: usage_ledger_default_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_usage_ledger_part_ts ATTACH PARTITION public.usage_ledger_default_ts_idx;



\unrestrict DjyOr1ZVtLd0kOQxXKtJinYncfEgIctN0Mvytkc2xC960WV2c8OoLqyPkVCNV1y


-- ----------------------------------------
-- Table: usage_ledger_old
-- ----------------------------------------






-- Name: usage_ledger_old; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.usage_ledger_old (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);


-- Name: usage_ledger_old usage_ledger_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.usage_ledger_old
    ADD CONSTRAINT usage_ledger_pkey PRIMARY KEY (request_id);



\unrestrict JaQQbz2bCFYaclKerVvpWa1Z4UIIcYDQXHoxUFH4o9nrX9gA7pmSOnyU1CuWREH


-- ----------------------------------------
-- Table: usage_minute
-- ----------------------------------------






-- Name: usage_minute; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.usage_minute (
    bucket timestamp with time zone NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    department text,
    employee text,
    "position" text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    requests bigint DEFAULT 0 NOT NULL,
    prompt_tokens bigint DEFAULT 0 NOT NULL,
    completion_tokens bigint DEFAULT 0 NOT NULL,
    total_tokens bigint DEFAULT 0 NOT NULL,
    cost_usd numeric(18,8) DEFAULT 0 NOT NULL,
    errors bigint DEFAULT 0 NOT NULL
);



\unrestrict TDMI7N5sIfJJQ6F2idMnFgpH9MP1BwVxeonVcHV7Uf8Q2bhlit2prwVRhZNOT2k


