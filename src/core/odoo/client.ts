/**
 * Odoo JSON-RPC client for browser and Node.
 *
 * Talks to an Odoo 18 Community instance over JSON-RPC (/jsonrpc endpoint)
 * using a static API key (preferred) or password. This is the integration
 * layer that lets the React UI sync Partners, Projects (as analytic
 * accounts), Transactions (as journal entries), and Payments (as
 * account.payment records) to the accounting backend.
 *
 * For Phase 1 the sync direction is Terranex → Odoo (one-way).
 *
 * References:
 * https://www.odoo.com/documentation/18.0/developer/reference/external_api.html
 */

const JSONRPC_ENDPOINT = '/jsonrpc';

// Note: Vite injects import.meta.env at build time via define/replace. We don't
// reference it directly here; instead consumers should call setOdooClient() or
// rely on the Vite virtual module shim that writes __ODOO_ENV__ before this
// module loads. To keep test builds (CJS) happy we never touch import.meta
// directly in code that TypeScript compiles.

export interface OdooConfig {
  url: string;
  db: string;
  username: string;
  apiKey: string;
}

export interface OdooCallKWParams {
  model: string;
  method: string;
  args?: unknown[];
  kwargs?: Record<string, unknown>;
}

interface JsonRpcResponse<T> {
  jsonrpc: '2.0';
  id: number;
  result?: T;
  error?: {
    code: number;
    message: string;
    data?: { name: string; message: string; debug?: string };
  };
}

export class OdooClient {
  private readonly baseUrl: string;
  private readonly db: string;
  private readonly username: string;
  private readonly apiKey: string;
  private uid: number | null = null;
  private nextId = 1;

  constructor(config: OdooConfig) {
    // strip trailing slash
    this.baseUrl = config.url.replace(/\/$/, '');
    this.db = config.db;
    this.username = config.username;
    this.apiKey = config.apiKey;
  }

  isConfigured(): boolean {
    return Boolean(this.baseUrl && this.db && this.username && this.apiKey);
  }

  /**
   * Authenticate and cache the user's uid. Safe to call multiple times —
   * re-authenticates only if not yet logged in.
   */
  async login(): Promise<number> {
    if (this.uid !== null) return this.uid;
    const uid = await this.call<number>('common', 'login', [
      this.db,
      this.username,
      this.apiKey,
    ]);
    if (!uid || typeof uid !== 'number') {
      throw new Error('فشل تسجيل الدخول إلى Odoo — تحقق من اسم المستخدم ومفتاح API.');
    }
    this.uid = uid;
    return uid;
  }

  async logout(): Promise<void> {
    this.uid = null;
  }

  /**
   * Call an Odoo model method (object.dispatch-style) — the standard way
   * to interact with records: search_read, create, write, unlink, ...
   */
  async callKW<T = unknown>(params: OdooCallKWParams): Promise<T> {
    const uid = await this.login();
    return this.call<T>('object', 'execute_kw', [
      this.db,
      uid,
      this.apiKey,
      params.model,
      params.method,
      params.args ?? [],
      params.kwargs ?? {},
    ]);
  }

  /** Shortcut: create a record and return its id. */
  async create(model: string, values: Record<string, unknown>): Promise<number> {
    const ids = await this.callKW<number[]>({
      model,
      method: 'create',
      args: [values],
    });
    return Array.isArray(ids) ? ids[0] : (ids as unknown as number);
  }

  /** Shortcut: update records by id. */
  async write(model: string, ids: number[], values: Record<string, unknown>): Promise<boolean> {
    return this.callKW<boolean>({
      model,
      method: 'write',
      args: [ids, values],
    });
  }

  /** Shortcut: search_read in one call (Odoo's convenience method). */
  async searchRead<T = Record<string, unknown>>(
    model: string,
    domain: unknown[] = [],
    fields: string[] = [],
    opts: { limit?: number; offset?: number; order?: string } = {},
  ): Promise<T[]> {
    const kwargs: Record<string, unknown> = { fields };
    if (opts.limit !== undefined) kwargs.limit = opts.limit;
    if (opts.offset !== undefined) kwargs.offset = opts.offset;
    if (opts.order !== undefined) kwargs.order = opts.order;
    return this.callKW<T[]>({
      model,
      method: 'search_read',
      args: [domain],
      kwargs,
    });
  }

  /** Low-level JSON-RPC dispatcher. */
  private async call<T>(service: string, method: string, args: unknown[]): Promise<T> {
    const body = {
      jsonrpc: '2.0',
      method: 'call',
      params: { service, method, args },
      id: this.nextId++,
    };
    const res = await fetch(`${this.baseUrl}${JSONRPC_ENDPOINT}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      throw new Error(`Odoo HTTP ${res.status}: ${res.statusText}`);
    }
    const data = (await res.json()) as JsonRpcResponse<T>;
    if (data.error) {
      const msg = data.error.data?.message || data.error.message || 'خطأ غير معروف من Odoo';
      throw new Error(`Odoo: ${msg}`);
    }
    return data.result as T;
  }
}

// ---------------------------------------------------------------------------
// Singleton + helpers for the Terranex React UI
// ---------------------------------------------------------------------------

let cachedClient: OdooClient | null = null;

/**
 * Build an OdooClient from Vite env vars (build time) OR from a runtime config
 * set via `setOdooClient()`. Returns null if Odoo is disabled in both.
 */
function readEnv(): null {
  // SECURITY: Browser-side Odoo client construction from env/settings is disabled.
  // VITE_ODOO_API_KEY is no longer read from the bundle (it is a privileged secret).
  // Synchronization will be performed server-side via Supabase Edge Function.
  return null;
}

let runtimeClient: OdooClient | null = null;

/** Allow callers to inject a client configured at runtime (e.g. from company_settings). */
export function setOdooClient(client: OdooClient | null): void {
  runtimeClient = client;
  cachedClient = client;
}

export function getOdooClient(): OdooClient | null {
  if (cachedClient) return cachedClient;
  if (runtimeClient) return runtimeClient;
  // readEnv() intentionally always returns null — browser-side construction is
  // disabled (see SECURITY note in readEnv). Synchronization runs server-side.
  return null;
}

/** Build an OdooClient from an explicit config object (used by runtime settings). */
export function createOdooClient(cfg: { url: string; db: string; username: string; apiKey: string }): OdooClient {
  return new OdooClient(cfg);
}

/** Reset the cached client (e.g., after changing settings). */
export function resetOdooClient(): void {
  cachedClient = null;
}
