/**
 * In-memory fake Supabase client for tests.
 * Mimics just enough of the real SupabaseClient API for supabaseStore.ts
 * to work (from, insert, update, delete, rpc, channel, etc.).
 *
 * Data stored in memory; no persistence, no auth, no RLS.
 * Each test should call resetFakeSupabase() before running.
 */

class FakeQueryBuilder {
  constructor(tableName, operation, data = null) {
    this.tableName = tableName;
    this.operation = operation;
    this.data = data;
    this.filters = [];
    this.orderConfig = null;
  }

  select(columns = '*') {
    return new FakeQueryBuilder(this.tableName, 'select', null);
  }

  order(column, { ascending = true } = {}) {
    this.orderConfig = { column, ascending };
    return this;
  }

  eq(column, value) {
    this.filters.push({ column, op: 'eq', value });
    return this;
  }

  in(column, values) {
    this.filters.push({ column, op: 'in', value: values });
    return this;
  }

  async then(resolve, reject) {
    try {
      const result = await this.execute();
      resolve(result);
    } catch (error) {
      reject(error);
    }
  }

  async execute() {
    const table = fakeDb[this.tableName];
    if (!table) {
      return { data: null, error: { message: `جدول ${this.tableName} غير موجود.` } };
    }

    let result = Array.from(table.values());

    // تطبيق الفلاتر
    for (const filter of this.filters) {
      if (filter.op === 'eq') {
        result = result.filter(row => row[filter.column] === filter.value);
      } else if (filter.op === 'in') {
        result = result.filter(row => filter.value.includes(row[filter.column]));
      }
    }

    // تطبيق الترتيب
    if (this.orderConfig) {
      result.sort((a, b) => {
        const aVal = a[this.orderConfig.column];
        const bVal = b[this.orderConfig.column];
        const cmp = aVal < bVal ? -1 : aVal > bVal ? 1 : 0;
        return this.orderConfig.ascending ? cmp : -cmp;
      });
    }

    if (this.operation === 'select') {
      return { data: result, error: null };
    } else if (this.operation === 'insert') {
      for (const row of this.data) {
        table.set(row.id, row);
      }
      return { data: this.data, error: null };
    } else if (this.operation === 'update') {
      for (const row of result) {
        const updated = { ...row, ...this.data };
        table.set(updated.id, updated);
      }
      return { data: result.map(row => ({ ...row, ...this.data })), error: null };
    } else if (this.operation === 'delete') {
      for (const row of result) {
        table.delete(row.id);
      }
      return { data: null, error: null };
    }

    return { data: null, error: { message: 'عملية غير معروفة.' } };
  }
}

const fakeDb = {};

class FakeSupabaseClient {
  from(tableName) {
    // تأكد أن الجدول موجود
    if (!fakeDb[tableName]) {
      fakeDb[tableName] = new Map();
    }
    return {
      select: (columns) => new FakeQueryBuilder(tableName, 'select').select(columns),
      insert: (data) => {
        const builder = new FakeQueryBuilder(tableName, 'insert', Array.isArray(data) ? data : [data]);
        // تحويل إلى Promise
        return {
          then: (resolve, reject) => {
            builder.execute().then(resolve, reject);
          }
        };
      },
      update: (data) => ({
        eq: (column, value) => {
          const builder = new FakeQueryBuilder(tableName, 'update', data);
          builder.eq(column, value);
          return {
            then: (resolve, reject) => {
              builder.execute().then(resolve, reject);
            }
          };
        }
      }),
      delete: () => ({
        in: (column, values) => {
          const builder = new FakeQueryBuilder(tableName, 'delete');
          builder.in(column, values);
          return {
            then: (resolve, reject) => {
              builder.execute().then(resolve, reject);
            }
          };
        }
      }),
      rpc: (fn, params) => {
        // RPC guard calls: هنرجع canDelete=true دايمًا للاختبارات للبساطة
        return Promise.resolve({
          data: [{ can_delete: true, message_ar: 'يمكن الحذف.' }],
          error: null
        });
      }
    };
  }

  channel(name) {
    return {
      on: () => this.channel(name),
      subscribe: () => {},
    };
  }

  removeAllChannels() {}
}

function resetFakeSupabase() {
  for (const key of Object.keys(fakeDb)) {
    fakeDb[key].clear();
  }
}

module.exports = { FakeSupabaseClient, resetFakeSupabase, fakeDb };
