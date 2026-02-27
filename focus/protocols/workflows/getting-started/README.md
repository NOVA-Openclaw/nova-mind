# AWL Getting Started Examples

These workflows accompany the **AWL Getting Started Guide** (`~/clawd/nova-cognition/docs/awl-getting-started.md`).

## Example Workflows

### 1. hello-world.awl.yaml
**Purpose:** Simplest possible AWL workflow  
**What it does:** Has an agent say hello and sends a notification  
**Learn:** Basic workflow structure, variables, agent tasks, notifications

**Run it:**
```bash
nova-workflow run workflows/getting-started/hello-world.awl.yaml \
  --var name="Nova" \
  --var agent_name="scribe"
```

### 2. write-with-approval.awl.yaml
**Purpose:** Content creation with human approval  
**What it does:** Agent writes draft → human approval → agent polishes → notification  
**Learn:** Multi-step workflows, approval gates, error handling, conditional execution

**Run it:**
```bash
nova-workflow run workflows/getting-started/write-with-approval.awl.yaml \
  --var topic="Machine learning basics" \
  --var approver="your-name"
```

### 3. parallel-research.awl.yaml
**Purpose:** Parallel task execution  
**What it does:** 3 agents research different aspects → 1 agent synthesizes → shares report  
**Learn:** Parallel execution, wait strategies, complex variable passing

**Run it:**
```bash
nova-workflow run workflows/getting-started/parallel-research.awl.yaml \
  --var research_topic="sustainable energy"
```

## Next Steps

After running these examples:

1. **Modify them** - Change variables, add steps, experiment
2. **Create your own** - Use these as templates for real workflows  
3. **Study advanced examples** - Look at `../create-new-agent.awl.yaml` and others
4. **Read the full docs** - `~/clawd/nova-cognition/docs/agent-workflow-language.md`

## Tips

- **Start simple** - Begin with hello-world, then build complexity
- **Test incrementally** - Add one step at a time
- **Use validation** - Run `nova-workflow validate your-workflow.awl.yaml`
- **Check logs** - If something fails, check `nova-workflow logs <workflow-id>`

Happy workflow building! 🚀