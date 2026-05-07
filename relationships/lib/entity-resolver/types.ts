/**
 * Entity type definitions for the entity resolver library
 */

export interface Entity {
  id: number;
  name: string;
  fullName?: string;
  type: string;
}

export interface EntityFacts {
  [key: string]: string;
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
}

/**
 * Internal database fact representation
 */
export interface DbEntityFact {
  key: string;
  value: string;
}
