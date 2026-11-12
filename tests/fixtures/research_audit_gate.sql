-- research_audit_gate.sql — throwaway schema fixtures for nova-mind#657 tests.
--
-- These tables mirror the live public.research_findings and
-- public.research_citations shape without the write-protection trigger, so the
-- test role can INSERT fixtures while still verifying the gate itself is
-- read-only. Tests create a private schema from this template, load data, run
-- the gate, assert row counts unchanged, and drop the schema.

CREATE SCHEMA IF NOT EXISTS {{schema}};

CREATE TABLE IF NOT EXISTS {{schema}}.research_findings (
    id integer PRIMARY KEY,
    task_id integer NOT NULL,
    finding_type character varying(50) NOT NULL,
    content text NOT NULL,
    confidence numeric(3,2),
    importance character varying(20) NOT NULL DEFAULT 'normal',
    version integer NOT NULL DEFAULT 1,
    is_current boolean NOT NULL DEFAULT true,
    superseded_by integer,
    superseded_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    search_vector tsvector
);

CREATE TABLE IF NOT EXISTS {{schema}}.research_citations (
    id integer PRIMARY KEY,
    finding_id integer NOT NULL REFERENCES {{schema}}.research_findings(id) ON DELETE CASCADE,
    source_type character varying(50) NOT NULL,
    source_url text,
    source_title character varying(500),
    source_author character varying(255),
    source_date date,
    quote text,
    page_or_section character varying(100),
    reliability numeric(3,2),
    library_work_id integer,
    accessed_at timestamp with time zone NOT NULL DEFAULT now(),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);
