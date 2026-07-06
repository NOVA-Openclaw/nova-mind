/**
 * Deterministic honorific guard.
 *
 * Builds an instruction string that enforces the NOVA honorific policy:
 *  - "Sir"/"Ma'am" and formal honorifics are prohibited for senders other than I)ruid.
 *  - When the sender is I)ruid and the agent is not NOVA, remind the agent that
 *    "Sir" is reserved exclusively for NOVA and address I)ruid normally.
 *  - When the sender is I)ruid and the agent is NOVA, no guard is emitted.
 *  - When the sender cannot be resolved, fail safe with the prohibition line.
 *
 * Binding ambiguity resolutions (nova-mind #421 A1-A7):
 *  - A2: agentId match is case-sensitive exact "nova", no normalization.
 *  - A3: preferredName is interpolated only in the rule-1 prohibition line;
 *        the exclusivity line always refers to "I)ruid" literally.
 *  - A4: No-guard path returns strict null.
 *  - A5: Entity check is first; unresolved entity → prohibition line, agentId
 *        is never consulted for that path. Exactly one guard string is emitted.
 */

const IRUID_ENTITY_ID = 2;

export function buildHonorificGuard(
  entityId: number | null | undefined,
  agentId: string | null | undefined,
  preferredName?: string
): string | null {
  // A5: Entity check first. Unresolved/unknown sender → fail-safe prohibition.
  if (entityId == null) {
    return buildProhibitionLine(preferredName);
  }

  // A2: Case-sensitive exact match on the agent name string.
  const isNova = agentId === "nova";

  // I)ruid sender.
  if (entityId === IRUID_ENTITY_ID) {
    // A3: Exclusivity line only when I)ruid is NOT talking to NOVA.
    if (!isNova) {
      return `The user is I)ruid. "Sir" is reserved exclusively for NOVA — address I)ruid normally using conversational pronouns.`;
    }
    // A4: I)ruid + NOVA → no guard.
    return null;
  }

  // Non-I)ruid sender → always prohibit formal honorifics, regardless of agent.
  return buildProhibitionLine(preferredName);
}

function buildProhibitionLine(preferredName?: string): string {
  if (preferredName != null && preferredName.trim().length > 0) {
    return `You are talking with ${preferredName}. Do not use "Sir", "Ma'am", or other formal honorifics — address ${preferredName} by name or with normal conversational pronouns.`;
  }
  return `Do not use "Sir", "Ma'am", or other formal honorifics — address this sender by name or with normal conversational pronouns.`;
}
