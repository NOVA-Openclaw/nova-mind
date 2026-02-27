-- Audit Triggers for Bootstrap Context System
-- Automatically log all INSERT, UPDATE, DELETE operations to bootstrap_context_audit

-- Trigger function for universal context audit
CREATE OR REPLACE FUNCTION audit_bootstrap_universal()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO bootstrap_context_audit (
            table_name, 
            record_id, 
            operation, 
            old_content, 
            new_content, 
            changed_by, 
            changed_at
        ) VALUES (
            'bootstrap_context_universal',
            OLD.id,
            'DELETE',
            OLD.content,
            NULL,
            OLD.updated_by,
            NOW()
        );
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO bootstrap_context_audit (
            table_name, 
            record_id, 
            operation, 
            old_content, 
            new_content, 
            changed_by, 
            changed_at
        ) VALUES (
            'bootstrap_context_universal',
            NEW.id,
            'UPDATE',
            OLD.content,
            NEW.content,
            NEW.updated_by,
            NOW()
        );
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO bootstrap_context_audit (
            table_name, 
            record_id, 
            operation, 
            old_content, 
            new_content, 
            changed_by, 
            changed_at
        ) VALUES (
            'bootstrap_context_universal',
            NEW.id,
            'INSERT',
            NULL,
            NEW.content,
            NEW.updated_by,
            NOW()
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger function for agent context audit
CREATE OR REPLACE FUNCTION audit_bootstrap_agents()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO bootstrap_context_audit (
            table_name, 
            record_id, 
            operation, 
            old_content, 
            new_content, 
            changed_by, 
            changed_at
        ) VALUES (
            'bootstrap_context_agents',
            OLD.id,
            'DELETE',
            OLD.content,
            NULL,
            OLD.updated_by,
            NOW()
        );
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO bootstrap_context_audit (
            table_name, 
            record_id, 
            operation, 
            old_content, 
            new_content, 
            changed_by, 
            changed_at
        ) VALUES (
            'bootstrap_context_agents',
            NEW.id,
            'UPDATE',
            OLD.content,
            NEW.content,
            NEW.updated_by,
            NOW()
        );
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO bootstrap_context_audit (
            table_name, 
            record_id, 
            operation, 
            old_content, 
            new_content, 
            changed_by, 
            changed_at
        ) VALUES (
            'bootstrap_context_agents',
            NEW.id,
            'INSERT',
            NULL,
            NEW.content,
            NEW.updated_by,
            NOW()
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers on universal context table
DROP TRIGGER IF EXISTS trg_audit_bootstrap_universal ON bootstrap_context_universal;
CREATE TRIGGER trg_audit_bootstrap_universal
AFTER INSERT OR UPDATE OR DELETE ON bootstrap_context_universal
FOR EACH ROW EXECUTE FUNCTION audit_bootstrap_universal();

-- Create triggers on agent context table
DROP TRIGGER IF EXISTS trg_audit_bootstrap_agents ON bootstrap_context_agents;
CREATE TRIGGER trg_audit_bootstrap_agents
AFTER INSERT OR UPDATE OR DELETE ON bootstrap_context_agents
FOR EACH ROW EXECUTE FUNCTION audit_bootstrap_agents();

COMMENT ON FUNCTION audit_bootstrap_universal IS 'Audit trigger function for universal context changes';
COMMENT ON FUNCTION audit_bootstrap_agents IS 'Audit trigger function for agent-specific context changes';
