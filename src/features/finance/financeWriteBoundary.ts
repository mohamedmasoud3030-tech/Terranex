import { requireClient } from '../../core/storage/supabaseClientRegistry';
import { assetsStore } from '../assets/storage';
import { stockAdjustmentsStore } from '../events/storage';
import { obligationsStore } from '../obligations/storage';
import { settlementAllocationsStore } from '../settlement-allocations/storage';
import { settlementsStore } from '../settlements/storage';
import { transactionsStore } from '../transactions/storage';

export const FINANCE_ATOMICITY_NOTICE = {
  ar: 'هذه العملية تُنفذ كمعاملة ذرية واحدة على الخادم، مع request_id لمنع التكرار وإعادة مزامنة البيانات بعد النجاح.',
  en: 'This operation runs as one server-side atomic transaction with request-id idempotency and refreshes data after success.',
};

export const P1B_ATOMIC_RPC_NAMES = [
  'record_transaction_atomic',
  'update_transaction_atomic',
  'delete_transaction_atomic',
  'record_settlement_atomic',
  'reverse_settlement_atomic',
  'record_stock_adjustment_atomic',
] as const;

export type P1BAtomicRpcName = typeof P1B_ATOMIC_RPC_NAMES[number];

/**
 * Namespace for Terranex financial request ids (a fixed random UUID).
 * Fixing it makes the derivation below reproducible across sessions and
 * devices, which is what allows a retried submit to collapse onto the same
 * request id that the server already recorded.
 */
const REQUEST_ID_NAMESPACE = '6f1a9d2e-4c3b-4f8a-9e7d-2b5c8a1f0d34';

/** Window within which two identical submits are treated as one intent. */
const DOUBLE_SUBMIT_WINDOW_MS = 2000;

function toUtf8Bytes(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.replace(/-/g, '');
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i += 1) {
    out[i] = Number.parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

/**
 * SHA-1 over a byte array. Implemented locally because request-id derivation
 * must be synchronous — `crypto.subtle.digest` is async and every caller here
 * builds its payload synchronously. This is a name-derivation hash, never a
 * security primitive.
 */
function sha1(bytes: Uint8Array): Uint8Array {
  const ml = bytes.length * 8;
  const withPadding = new Uint8Array((((bytes.length + 8) >> 6) + 1) * 64);
  withPadding.set(bytes);
  withPadding[bytes.length] = 0x80;
  const view = new DataView(withPadding.buffer);
  view.setUint32(withPadding.length - 4, ml >>> 0, false);
  view.setUint32(withPadding.length - 8, Math.floor(ml / 0x100000000), false);

  let h0 = 0x67452301;
  let h1 = 0xefcdab89;
  let h2 = 0x98badcfe;
  let h3 = 0x10325476;
  let h4 = 0xc3d2e1f0;
  const w = new Uint32Array(80);

  for (let offset = 0; offset < withPadding.length; offset += 64) {
    for (let i = 0; i < 16; i += 1) w[i] = view.getUint32(offset + i * 4, false);
    for (let i = 16; i < 80; i += 1) {
      const n = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
      w[i] = (n << 1) | (n >>> 31);
    }
    let [a, b, c, d, e] = [h0, h1, h2, h3, h4];
    for (let i = 0; i < 80; i += 1) {
      let f: number;
      let k: number;
      if (i < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
      else if (i < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
      else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
      else { f = b ^ c ^ d; k = 0xca62c1d6; }
      const temp = (((a << 5) | (a >>> 27)) + f + e + k + w[i]) >>> 0;
      e = d; d = c; c = (b << 30) | (b >>> 2); b = a; a = temp;
    }
    h0 = (h0 + a) >>> 0;
    h1 = (h1 + b) >>> 0;
    h2 = (h2 + c) >>> 0;
    h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0;
  }

  const out = new Uint8Array(20);
  new DataView(out.buffer).setUint32(0, h0, false);
  new DataView(out.buffer).setUint32(4, h1, false);
  new DataView(out.buffer).setUint32(8, h2, false);
  new DataView(out.buffer).setUint32(12, h3, false);
  new DataView(out.buffer).setUint32(16, h4, false);
  return out;
}

/** RFC 4122 v5 (SHA-1, name-based) UUID. */
function uuidV5(name: string, namespace: string): string {
  const ns = hexToBytes(namespace);
  const nameBytes = toUtf8Bytes(name);
  const input = new Uint8Array(ns.length + nameBytes.length);
  input.set(ns);
  input.set(nameBytes, ns.length);

  const hash = sha1(input);
  hash[6] = (hash[6] & 0x0f) | 0x50; // version 5
  hash[8] = (hash[8] & 0x3f) | 0x80; // RFC 4122 variant

  const hex = Array.from(hash.slice(0, 16))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return [
    hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16),
    hex.slice(16, 20), hex.slice(20, 32),
  ].join('-');
}

/**
 * Derives the idempotency key for one atomic financial write.
 *
 * The server treats `p_request_id` as the deduplication key: a replay of the
 * same id returns the cached result instead of writing twice. A random UUID
 * therefore only protects against network-level retries — it does nothing for
 * a user double-clicking "save", because each click produced a fresh id.
 *
 * The id is now derived from what the operation *is*:
 *
 *   uuidv5(operation + business keys + discriminator)
 *
 * The discriminator is either
 *   - a caller-supplied draft id (preferred): the form instance owns it, so two
 *     clicks on the same form collapse to one id while two deliberate, separate
 *     entries — even identical amounts to the same partner — each own a distinct
 *     draft and stay distinct; or
 *   - a 2-second time bucket (fallback) when no draft id is supplied.
 *
 * The draft id is what keeps this correct. A pure time bucket would also merge
 * two intentional identical payments made seconds apart, which would silently
 * drop a real transaction.
 *
 * @param operation  RPC name, e.g. 'record_transaction_atomic'
 * @param keys       business identity of the write (ids, amounts, dates).
 *                   Pass a stable draft/form id first when one exists.
 */
export function generateRequestId(operation?: string, ...keys: string[]): string {
  const provided = keys.filter((key) => key !== undefined && key !== null && key !== '');

  // No operation context at all: fall back to a random id rather than collapsing
  // unrelated writes onto one key.
  if (!operation && provided.length === 0) return crypto.randomUUID();

  const hasDraftId = provided.length > 0;
  const discriminator = hasDraftId
    ? ''
    : `:t${Math.floor(Date.now() / DOUBLE_SUBMIT_WINDOW_MS)}`;

  return uuidV5(`${operation ?? 'unknown'}:${provided.join('|')}${discriminator}`, REQUEST_ID_NAMESPACE);
}

const financeStores = [
  transactionsStore,
  obligationsStore,
  settlementsStore,
  settlementAllocationsStore,
];

const stockStores = [assetsStore, stockAdjustmentsStore];

async function rehydrate(stores: Array<{ rehydrate(): Promise<void> }>): Promise<void> {
  await Promise.all(stores.map((store) => store.rehydrate()));
}

export async function rehydrateFinanceStores(): Promise<void> {
  await rehydrate(financeStores);
}

export async function rehydrateStockStores(): Promise<void> {
  await rehydrate(stockStores);
}

function toRpcError(error: unknown, rpc: string): Error {
  if (error instanceof Error) return error;
  if (error && typeof error === 'object' && 'message' in error) {
    return new Error(String((error as { message: unknown }).message));
  }
  return new Error(`فشل تنفيذ العملية الذرية ${rpc}.`);
}

function unwrapRpcResult<T>(data: unknown): T {
  if (Array.isArray(data) && data.length === 1) return data[0] as T;
  return data as T;
}

export interface InvokeFinanceRpcOptions {
  refresh?: 'finance' | 'stock' | 'none';
}

export async function invokeFinanceRpc<T>(
  rpc: P1BAtomicRpcName,
  params: object,
  options: InvokeFinanceRpcOptions = {},
): Promise<T> {
  const refresh = options.refresh ?? 'finance';
  const client = requireClient();
  const { data, error } = await client.rpc(rpc, params as Record<string, unknown>);

  if (error) {
    if (refresh === 'finance') await rehydrateFinanceStores();
    if (refresh === 'stock') await rehydrateStockStores();
    throw toRpcError(error, rpc);
  }

  if (refresh === 'finance') await rehydrateFinanceStores();
  if (refresh === 'stock') await rehydrateStockStores();
  return unwrapRpcResult<T>(data);
}

export async function executeFinanceWrite<T>(operation: () => T | Promise<T>): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    await rehydrateFinanceStores();
    throw error;
  }
}
