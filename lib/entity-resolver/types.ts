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
}

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
