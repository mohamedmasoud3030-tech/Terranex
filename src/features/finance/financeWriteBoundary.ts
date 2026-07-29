import { obligationsStore } from '../obligations/storage';
import { settlementAllocationsStore } from '../settlement-allocations/storage';
import { settlementsStore } from '../settlements/storage';
import { transactionsStore } from '../transactions/storage';

export const FINANCE_ATOMICITY_NOTICE = {
  ar: 'هذه العملية تستخدم عدة طلبات حاليًا وليست معاملة قاعدة بيانات ذرية. لا تُعرض كناجحة قبل اكتمال كل الكتابات.',
  en: 'This operation currently uses multiple requests and is not a database transaction. It is not reported as successful until every write finishes.',
};

const stores = [
  transactionsStore,
  obligationsStore,
  settlementsStore,
  settlementAllocationsStore,
];

async function rehydrateFinanceStores(): Promise<void> {
  await Promise.all(stores.map((store) => store.rehydrate()));
}

export async function flushFinanceWrites(): Promise<void> {
  try {
    await Promise.all(stores.map((store) => store.flush()));
  } catch (error) {
    await rehydrateFinanceStores();
    throw error;
  }
}

export async function executeFinanceWrite<T>(operation: () => T): Promise<T> {
  try {
    const result = operation();
    await flushFinanceWrites();
    return result;
  } catch (error) {
    await rehydrateFinanceStores();
    throw error;
  }
}
