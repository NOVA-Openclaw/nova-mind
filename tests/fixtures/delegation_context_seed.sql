-- Fixture for generate-delegation-context.sh tests.
-- Assumes the disposable schema delegation_context_test already exists and is
-- writable by the test user. The BATS setup creates the schema as the nova DB
-- user; the fixture is applied as the coder DB user.
SET search_path TO delegation_context_test;

DROP TABLE IF EXISTS agents CASCADE;
DROP TABLE IF EXISTS workflows CASCADE;
DROP TABLE IF EXISTS workflow_steps_detail CASCADE;

CREATE TABLE agents (
    id serial PRIMARY KEY,
    name text NOT NULL,
    nickname text,
    role text,
    model text,
    description text,
    status text,
    instance_type text,
    thinking text,
    context_type text,
    allowed_subagents text[],
    decision_criteria text
);

CREATE TABLE workflows (
    id serial PRIMARY KEY,
    name text NOT NULL,
    description text,
    status text
);

CREATE TABLE workflow_steps_detail (
    workflow_name text,
    workflow_description text,
    step_order int,
    domain text,
    domains text[],
    step_description text,
    produces_deliverable bool,
    deliverable_type text,
    deliverable_description text,
    estimated_duration_minutes int
);

-- Agents covering: decision_criteria populated, NULL, empty array, NULL array.
INSERT INTO agents (name, nickname, role, model, description, status, instance_type, thinking, context_type, allowed_subagents, decision_criteria) VALUES
    ('agent-alpha', 'alpha', 'Coder', 'model-a', 'Primary coding agent', 'active', 'subagent', 'low', 'persistent', ARRAY['beta'], 'Handle coding tasks'),
    ('agent-beta',  'beta',  'Tester','model-b', 'QA agent',            'active', 'subagent', 'minimal', 'ephemeral', ARRAY[]::text[], NULL),
    ('agent-gamma', 'gamma', 'Peer',  'model-c', 'Peer helper',         'active', 'peer',     'high', 'persistent', NULL, NULL);

-- Workflows covering: normal, apostrophe, heading collision, zero steps.
INSERT INTO workflows (name, description, status) VALUES
    ('Normal Workflow', 'A normal workflow for everyday use.', 'active'),
    ('Test''s Workflow', 'Workflow with an apostrophe in the name.', 'active'),
    ('Heading Collision Workflow', E'# Not A Heading\n## Also Not A Heading\nRegular text.', 'active'),
    ('Zero Step Workflow', 'This workflow has no steps.', 'active'),
    ('Inactive Workflow', 'Should not appear.', 'inactive');

-- Steps covering: single domain, multi-domain.
INSERT INTO workflow_steps_detail (workflow_name, step_order, domain, domains, step_description, deliverable_type) VALUES
    ('Normal Workflow',            1, 'Engineering', ARRAY['Engineering'],        'Implement feature', 'code'),
    ('Normal Workflow',            2, 'QA',          ARRAY['QA','Engineering'],   'Review feature',    'report'),
    ('Test''s Workflow',           1, 'QA',          ARRAY['QA'],                 'Test apostrophe',   'test'),
    ('Heading Collision Workflow', 1, 'Engineering', ARRAY['Engineering'],        'Do the thing',      'output');
