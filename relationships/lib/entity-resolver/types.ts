/**
 * Entity type definitions for the entity resolver library
 */

export interface Entity {
  id: number;
  name: string;
  fullName?: string;
  type: string;
  pronouns?: string;
  trustLevel?: string;
  lastSeen?: string;
  createdAt?: string;
}

export interface EntityFacts {
  [key: string]: string;
}

/**
 * Relationship stats for an entity.
 */
export interface EntityRelationshipStats {
  factCount: number;
  lastMessage: {
    timestamp: string;
    ref: string;
  } | null;
}

/**
 * Entity profile returned by getEntityProfile().
 * Combines the existing allowlist facts with cheap relationship stats.
 */
export interface EntityProfile {
  facts: EntityFacts;
  stats: EntityRelationshipStats;
}

/**
 * Identifiers that can be used to resolve an entity
 */
export interface EntityIdentifiers {
  phone?: string;
  uuid?: string;
  certCN?: string;
  email?: string;
  discordId?: string;
  telegramId?: string;
  slackMemberId?: string;
  signalUuid?: string;
  signalUsername?: string;
  deviceId?: string;  // OpenClaw device pairing ID (Ed25519 pubkey hash)
  ircUsername?: string;  // composite <network>/<nick>, e.g. late.sh/druidian
}

/**
 * Result of entity resolution when identifiers may match multiple entities.
 * - ok: true  → all identifiers resolved to the same entity
 * - ok: false → identifiers resolved to different entities (data integrity conflict)
 */
export type ResolveResult =
  | { ok: true; entity: Entity; facts: DbEntityFact[] }
  | { ok: false; conflict: true; entities: Entity[]; message: string };

/**
 * Internal database entity representation
 */
export interface DbEntity {
  id: number;
  name: string;
  full_name: string | null;
  type?: string;
  pronouns?: string | null;
  trust_level?: string | null;
  last_seen?: string | null;
  created_at?: string | null;
}

/**
 * Internal database fact representation
 */
export interface DbEntityFact {
  key: string;
  value: string;
}
