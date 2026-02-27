-- Test Dataset for nova-memory
-- Fabricated but realistic data for testing the memory system
-- Including semantic recall and privacy features

-- ============================================================================
-- ENTITIES (15 total: people, organizations, AI agents)
-- ============================================================================

INSERT INTO entities (id, name, type, full_name, nicknames, gender, pronouns, notes, trust_level, preferred_contact) VALUES
-- People (8)
(1, 'Alice', 'person', 'Alice Testuser', ARRAY['Al', 'Ally'], 'female', 'she/her', 'Primary test user - software engineer', 'trusted', 'email'),
(2, 'Bob', 'person', 'Bob Builder', ARRAY['Bobby', 'The Builder'], 'male', 'he/him', 'Secondary contact - works at Acme Corp', 'known', 'phone'),
(3, 'Charlie', 'person', 'Charlie Chen', ARRAY['Chuck'], 'male', 'he/him', 'Data scientist and coffee enthusiast', 'known', 'slack'),
(4, 'Diana', 'person', 'Diana Prince', ARRAY['Di'], 'female', 'she/her', 'Project manager with strong opinions on agile', 'trusted', 'email'),
(5, 'Eve', 'person', 'Eve Anderson', NULL, 'female', 'she/her', 'Security researcher - privacy advocate', 'known', 'signal'),
(6, 'Frank', 'person', 'Frank O''Reilly', ARRAY['Frankie'], 'male', 'he/him', 'Marketing lead - loves special characters in name', 'known', 'email'),
(7, 'Grace', 'person', 'Grace Hopper-Smith', NULL, 'female', 'they/them', 'DevOps engineer with hyphenated name', 'trusted', 'slack'),
(8, 'Hank', 'person', 'Henry "Hank" Peterson', ARRAY['Hank'], 'male', 'he/him', 'CEO of TechStart Inc - very long meetings', 'known', 'email'),

-- Organizations (4)
(9, 'Acme Corp', 'organization', 'Acme Corporation', ARRAY['Acme', 'ACME'], NULL, NULL, 'Fictional company - makes everything', 'known', NULL),
(10, 'TechStart Inc', 'organization', 'TechStart Incorporated', ARRAY['TechStart'], NULL, NULL, 'Startup focused on AI tools', 'trusted', NULL),
(11, 'OpenSource Foundation', 'organization', 'The OpenSource Foundation', ARRAY['OSF'], NULL, NULL, 'Non-profit supporting open source', 'known', NULL),
(12, 'DataViz Labs', 'organization', 'DataViz Research Labs', ARRAY['DataViz'], NULL, NULL, 'Research organization - data visualization', 'known', NULL),

-- AI Agents (3)
(13, 'TestBot', 'ai', 'Test Bot Alpha', ARRAY['TB', 'TestBot'], NULL, NULL, 'Primary test agent for automation', 'trusted', NULL),
(14, 'AnalyticsBot', 'ai', 'Analytics Assistant', ARRAY['Analytics'], NULL, NULL, 'Data analysis specialist bot', 'known', NULL),
(15, 'SecurityBot', 'ai', 'Security Guardian', ARRAY['SecBot'], NULL, NULL, 'Security monitoring agent', 'trusted', NULL);

-- Reset sequence
SELECT setval('entities_id_seq', 15, true);

-- ============================================================================
-- ENTITY FACTS (75 facts with various visibility levels and edge cases)
-- ============================================================================

INSERT INTO entity_facts (entity_id, key, value, source, confidence, visibility, data_type) VALUES
-- Alice (person 1) - 15 facts
(1, 'favorite_color', 'blue', 'direct_conversation', 1.0, 'public', 'preference'),
(1, 'programming_languages', 'Python, JavaScript, Go', 'profile', 0.95, 'public', 'observation'),
(1, 'favorite_food', 'Thai curry', 'conversation', 0.9, 'public', 'preference'),
(1, 'email', 'alice@testuser.example', 'profile', 1.0, 'public', 'identity'),
(1, 'phone', '+1-555-0101', 'contact_card', 1.0, 'hidden', 'identity'),
(1, 'birthday', '1995-03-15', 'profile', 1.0, 'sensitive', 'permanent'),
(1, 'employer', 'TechStart Inc', 'linkedin', 0.95, 'public', 'observation'),
(1, 'job_title', 'Senior Software Engineer', 'linkedin', 0.95, 'public', 'observation'),
(1, 'works_remotely', 'true', 'conversation', 0.85, 'public', 'observation'),
(1, 'timezone', 'America/Los_Angeles', 'system', 0.9, 'public', 'observation'),
(1, 'coffee_preference', 'oat milk latte, no sugar', 'observation', 0.8, 'public', 'preference'),
(1, 'allergies', 'peanuts, shellfish', 'medical_record', 1.0, 'sensitive', 'permanent'),
(1, 'github_username', 'alice-testuser', 'profile', 0.95, 'public', 'identity'),
(1, 'favorite_editor', 'VS Code with vim keybindings', 'observation', 0.9, 'public', 'preference'),
(1, 'weekend_hobby', 'rock climbing and hiking', 'conversation', 0.85, 'public', 'observation'),

-- Bob (person 2) - 10 facts
(2, 'employer', 'Acme Corp', 'linkedin', 1.0, 'public', 'observation'),
(2, 'job_title', 'Build Engineer', 'linkedin', 0.95, 'public', 'observation'),
(2, 'favorite_color', 'red', 'conversation', 0.7, 'public', 'preference'),
(2, 'email', 'bob.builder@acme.example', 'business_card', 1.0, 'public', 'identity'),
(2, 'phone', '+1-555-0202', 'business_card', 1.0, 'hidden', 'identity'),
(2, 'years_of_experience', '12 years in DevOps', 'conversation', 0.8, 'public', 'observation'),
(2, 'certifications', 'AWS Certified Solutions Architect', 'linkedin', 0.95, 'public', 'observation'),
(2, 'favorite_tool', 'Docker and Kubernetes', 'tech_talk', 0.9, 'public', 'preference'),
(2, 'location', 'Austin, Texas', 'profile', 0.9, 'public', 'observation'),
(2, 'loves_bbq', 'true - especially brisket', 'conversation', 0.8, 'public', 'observation'),

-- Charlie (person 3) - 8 facts
(3, 'employer', 'DataViz Labs', 'email_signature', 0.95, 'public', 'observation'),
(3, 'job_title', 'Senior Data Scientist', 'linkedin', 0.95, 'public', 'observation'),
(3, 'favorite_language', 'R and Python for data science', 'tech_blog', 0.9, 'public', 'preference'),
(3, 'coffee_obsession', 'third-wave specialty coffee only', 'conversation', 0.95, 'public', 'preference'),
(3, 'email', 'charlie.chen@dataviz.example', 'email', 1.0, 'public', 'identity'),
(3, 'favorite_visualization', 'scatter plots with proper color theory', 'presentation', 0.85, 'public', 'preference'),
(3, 'conference_speaker', 'PyData and JupyterCon regular', 'observation', 0.9, 'public', 'observation'),
(3, 'side_project', 'building a coffee review app', 'github', 0.8, 'public', 'observation'),

-- Diana (person 4) - 7 facts
(4, 'employer', 'Acme Corp', 'business_card', 0.95, 'public', 'observation'),
(4, 'job_title', 'Senior Project Manager', 'business_card', 0.95, 'public', 'observation'),
(4, 'methodology_preference', 'Scrum with strict sprint boundaries', 'observation', 0.9, 'public', 'preference'),
(4, 'email', 'diana.prince@acme.example', 'email', 1.0, 'public', 'identity'),
(4, 'hates_meetings', 'meetings after 4pm or before 9am', 'calendar_policy', 0.95, 'public', 'preference'),
(4, 'certification', 'PMP and Certified Scrum Master', 'linkedin', 0.9, 'public', 'observation'),
(4, 'favorite_tool', 'Jira and Confluence', 'observation', 0.85, 'public', 'preference'),

-- Eve (person 5) - 6 facts (privacy-focused)
(5, 'employer', 'OpenSource Foundation', 'public_profile', 0.9, 'public', 'observation'),
(5, 'job_title', 'Security Researcher', 'conference_bio', 0.9, 'public', 'observation'),
(5, 'privacy_advocate', 'strong believer in data minimization', 'observation', 1.0, 'public', 'observation'),
(5, 'email', 'eve@protonmail.example', 'pgp_key', 1.0, 'hidden', 'identity'),
(5, 'uses_tor', 'true', 'observation', 0.7, 'sensitive', 'observation'),
(5, 'favorite_crypto', 'Signal protocol and E2EE', 'tech_talk', 0.95, 'public', 'preference'),

-- Frank (person 6) - 5 facts (tests special characters)
(6, 'employer', 'TechStart Inc', 'email_signature', 0.9, 'public', 'observation'),
(6, 'job_title', 'Head of Marketing & Growth', 'linkedin', 0.95, 'public', 'observation'),
(6, 'favorite_quote', 'Don''t just market—tell a story!', 'conversation', 0.8, 'public', 'observation'),
(6, 'email', 'frank.oreilly@techstart.example', 'business_card', 1.0, 'public', 'identity'),
(6, 'loves_emojis', '🚀 Uses emojis in all communications', 'observation', 1.0, 'public', 'observation'),

-- Grace (person 7) - 5 facts
(7, 'employer', 'OpenSource Foundation', 'gitlab_profile', 0.95, 'public', 'observation'),
(7, 'job_title', 'DevOps Engineer', 'gitlab_profile', 0.95, 'public', 'observation'),
(7, 'favorite_tool', 'Terraform and Ansible', 'tech_blog', 0.9, 'public', 'preference'),
(7, 'email', 'grace@opensourcefdn.example', 'email', 1.0, 'public', 'identity'),
(7, 'infrastructure_preference', 'infrastructure as code - everything versioned', 'philosophy', 1.0, 'public', 'observation'),

-- Hank (person 8) - 4 facts
(8, 'employer', 'TechStart Inc', 'company_website', 1.0, 'public', 'observation'),
(8, 'job_title', 'CEO and Founder', 'company_website', 1.0, 'public', 'observation'),
(8, 'meeting_style', 'prefers 2-hour deep dives over quick syncs', 'observation', 0.85, 'public', 'preference'),
(8, 'email', 'hank@techstart.example', 'business_card', 1.0, 'public', 'identity'),

-- Acme Corp (org 9) - 5 facts
(9, 'industry', 'Manufacturing and Technology', 'website', 0.95, 'public', 'observation'),
(9, 'headquarters', 'San Francisco, CA', 'website', 0.95, 'public', 'observation'),
(9, 'employee_count', 'approximately 5000 employees', 'linkedin', 0.8, 'public', 'observation'),
(9, 'founded', '1995', 'company_history', 0.95, 'public', 'permanent'),
(9, 'known_for', 'making everything from anvils to software', 'observation', 0.9, 'public', 'observation'),

-- TechStart Inc (org 10) - 5 facts
(10, 'industry', 'Artificial Intelligence and SaaS', 'website', 1.0, 'public', 'observation'),
(10, 'headquarters', 'Seattle, WA', 'website', 1.0, 'public', 'observation'),
(10, 'employee_count', '50-100 employees', 'estimation', 0.7, 'public', 'observation'),
(10, 'founded', '2022', 'press_release', 1.0, 'public', 'permanent'),
(10, 'funding', 'Series A - $15M raised', 'crunchbase', 0.95, 'public', 'observation'),

-- OpenSource Foundation (org 11) - 3 facts
(11, 'type', 'Non-profit organization', 'website', 1.0, 'public', 'observation'),
(11, 'mission', 'Supporting open source software development', 'about_page', 1.0, 'public', 'observation'),
(11, 'founded', '2010', 'about_page', 1.0, 'public', 'permanent'),

-- DataViz Labs (org 12) - 2 facts
(12, 'industry', 'Research and Data Visualization', 'website', 0.95, 'public', 'observation'),
(12, 'specialization', 'Advanced visualization techniques and tools', 'research_papers', 0.9, 'public', 'observation'),

-- TestBot (ai 13) - 3 facts
(13, 'capabilities', 'automated testing, CI/CD integration', 'configuration', 1.0, 'public', 'observation'),
(13, 'uptime', '99.9% availability', 'monitoring', 0.95, 'public', 'observation'),
(13, 'api_version', 'v2.1.0', 'system', 1.0, 'public', 'observation'),

-- AnalyticsBot (ai 14) - 2 facts
(14, 'capabilities', 'data analysis, visualization generation', 'configuration', 1.0, 'public', 'observation'),
(14, 'trained_on', 'statistical models and ML algorithms', 'documentation', 0.9, 'public', 'observation'),

-- SecurityBot (ai 15) - 2 facts
(15, 'capabilities', 'threat detection, security monitoring', 'configuration', 1.0, 'public', 'observation'),
(15, 'alert_threshold', 'medium and above', 'configuration', 1.0, 'hidden', 'observation');

-- ============================================================================
-- EVENTS (15 events - milestones, meetings, decisions)
-- ============================================================================

INSERT INTO events (id, event_date, title, description, source, confidence) VALUES
(1, '2024-01-15 14:00:00', 'TechStart Inc Kickoff Meeting', 'Company-wide meeting to announce Q1 2024 goals and priorities. Hank presented the vision for AI-powered tools.', 'calendar', 1.0),
(2, '2024-02-01 10:00:00', 'Alice Joined TechStart', 'Alice Testuser started as Senior Software Engineer at TechStart Inc.', 'hr_system', 1.0),
(3, '2024-02-14 16:00:00', 'Project Nova Memory Proposal', 'Alice proposed building a semantic memory system for AI agents. Team approved initial POC.', 'meeting_notes', 0.95),
(4, '2024-03-10 09:30:00', 'Architecture Review with Bob', 'Bob Builder provided feedback on memory system architecture. Suggested using PostgreSQL with pgvector.', 'meeting_notes', 0.9),
(5, '2024-03-22 13:00:00', 'OpenSource Foundation Partnership', 'TechStart and OpenSource Foundation announced collaboration on open source AI tools.', 'press_release', 1.0),
(6, '2024-04-05 15:00:00', 'Charlie''s Coffee Data Presentation', 'Charlie Chen presented analysis of coffee consumption patterns in tech companies. Surprisingly insightful.', 'calendar', 0.85),
(7, '2024-04-18 11:00:00', 'Security Audit by Eve', 'Eve Anderson conducted security review of memory system. Identified privacy concerns with embedding storage.', 'audit_report', 0.95),
(8, '2024-05-02 10:00:00', 'Sprint Planning - Privacy Features', 'Diana led sprint planning. Team committed to implementing visibility levels for entity facts.', 'jira', 0.9),
(9, '2024-05-20 14:30:00', 'TestBot Integration Success', 'TestBot successfully integrated with memory system. Automated testing coverage reached 85%.', 'ci_cd_log', 1.0),
(10, '2024-06-08 16:00:00', 'Acme Corp Collaboration Discussion', 'Bob facilitated discussion between TechStart and Acme Corp about potential enterprise deployment.', 'meeting_notes', 0.8),
(11, '2024-06-25 09:00:00', 'DataViz Labs Demo', 'Charlie demonstrated memory system integration with DataViz tools. Impressed the research team.', 'event_log', 0.85),
(12, '2024-07-10 13:00:00', 'Frank''s Marketing Campaign Launch', 'TechStart launched "Memory That Matters" campaign. Frank''s team used 🚀 emoji extensively.', 'marketing_calendar', 0.9),
(13, '2024-08-01 10:00:00', 'Infrastructure Overhaul Complete', 'Grace finished migrating memory system to containerized infrastructure. Zero downtime deployment achieved.', 'deployment_log', 1.0),
(14, '2024-09-15 14:00:00', 'Series A Funding Announcement', 'TechStart announced $15M Series A funding. Hank committed to expanding memory team.', 'press_release', 1.0),
(15, '2024-10-01 11:00:00', 'SecurityBot Deployed to Production', 'SecurityBot now actively monitoring memory system for security threats and anomalies.', 'deployment_log', 0.95);

-- Reset sequence
SELECT setval('events_id_seq', 15, true);

-- ============================================================================
-- LESSONS (8 lessons - learnings from experience)
-- ============================================================================

INSERT INTO lessons (id, lesson, context, source, confidence, original_behavior, correction_source) VALUES
(1, 'Always validate user input before storing in entity facts', 'Discovered SQL injection vulnerability in early version', 'security_audit', 1.0, 'Direct string interpolation', 'Eve Anderson security review'),
(2, 'Semantic search requires high-quality embeddings', 'Initial tests with poor embeddings yielded irrelevant results', 'testing', 0.95, 'Using default embeddings without tuning', 'Alice and Charlie collaboration'),
(3, 'Privacy levels must be enforced at query time, not just storage', 'Embeddings can leak sensitive information if not properly filtered', 'security_audit', 1.0, 'Storing all facts in embeddings', 'Eve Anderson recommendation'),
(4, 'Users prefer natural language queries over structured filters', 'User testing showed 80% preference for semantic search', 'user_research', 0.9, 'Complex filter UI', 'Diana''s UX research'),
(5, 'Container orchestration requires proper health checks', 'Early deployment failures due to missing liveness probes', 'incident_report', 0.95, 'No health check endpoints', 'Grace''s infrastructure review'),
(6, 'Test data should include edge cases and special characters', 'Frank O''Reilly''s name initially broke the import system', 'testing', 0.9, 'Only testing ASCII names', 'Integration testing discovery'),
(7, 'Documentation is crucial for API adoption', 'External partners struggled without clear API documentation', 'partner_feedback', 0.85, 'Minimal API docs', 'Frank''s partner survey'),
(8, 'Automated testing catches regressions early', 'TestBot integration prevented 15+ bugs from reaching production', 'metrics', 1.0, 'Manual testing only', 'Bob''s CI/CD implementation');

-- Reset sequence
SELECT setval('lessons_id_seq', 8, true);

-- ============================================================================
-- TASKS (12 tasks - various statuses and priorities)
-- ============================================================================

INSERT INTO tasks (id, title, description, status, priority, assigned_to, created_by, due_date, notes, blocked, blocked_reason) VALUES
(1, 'Implement semantic search API', 'Build REST API endpoint for semantic memory search', 'complete', 8, 1, 8, '2024-03-01', 'Completed ahead of schedule', false, NULL),
(2, 'Add privacy filters to embeddings', 'Ensure sensitive data is never included in embeddings', 'complete', 10, 1, 5, '2024-04-15', 'Critical for security compliance', false, NULL),
(3, 'Write API documentation', 'Comprehensive documentation for memory system API', 'in_progress', 7, 6, 4, '2024-11-30', 'Frank working with tech writers', false, NULL),
(4, 'Optimize embedding generation performance', 'Current embedding generation is too slow for large datasets', 'in_progress', 6, 3, 1, '2024-12-15', 'Charlie investigating batch processing', false, NULL),
(5, 'Set up monitoring dashboards', 'Create Grafana dashboards for system health', 'complete', 7, 7, 2, '2024-08-01', 'Grace deployed with infrastructure', false, NULL),
(6, 'Implement entity relationship tracking', 'Track relationships between entities (works_with, manages, etc.)', 'pending', 5, 1, 4, '2025-01-15', 'Blocked by schema changes', true, 'Waiting for database migration approval'),
(7, 'Add support for temporal facts', 'Facts that change over time (e.g., job titles)', 'pending', 6, 1, 4, '2025-02-01', 'Design phase', false, NULL),
(8, 'Integrate with Acme Corp systems', 'Enterprise integration for Acme Corp deployment', 'in_progress', 8, 2, 8, '2024-12-31', 'Bob coordinating with Acme IT team', false, NULL),
(9, 'Expand test coverage to 95%', 'Increase automated test coverage from 85% to 95%', 'in_progress', 6, 13, 2, '2024-11-15', 'TestBot running additional test suites', false, NULL),
(10, 'Research vector database alternatives', 'Evaluate Pinecone, Weaviate, and Milvus as alternatives', 'pending', 4, 3, 1, '2025-03-01', 'Charlie to lead research', false, NULL),
(11, 'Security penetration testing', 'Third-party security assessment of memory system', 'pending', 9, 5, 8, '2024-12-20', 'Waiting for security vendor contract', true, 'Procurement process in progress'),
(12, 'Build admin dashboard', 'Web UI for managing entities and facts', 'pending', 5, 6, 8, '2025-01-30', 'Nice to have for v2.0', false, NULL);

-- Reset sequence
SELECT setval('tasks_id_seq', 12, true);

-- ============================================================================
-- Summary Statistics (for verification)
-- ============================================================================

-- Expected counts:
-- entities: 15 (8 people, 4 organizations, 3 AI agents)
-- entity_facts: 75 (various visibility levels)
-- events: 15
-- lessons: 8
-- tasks: 12 (3 complete, 4 in_progress, 5 pending, 2 blocked)

-- Visibility distribution in entity_facts:
-- public: ~60 facts
-- hidden: ~10 facts
-- sensitive: ~5 facts
