/** Identifier generation shared by every feature store. */
export function newId(): string {
  return crypto.randomUUID();
}
