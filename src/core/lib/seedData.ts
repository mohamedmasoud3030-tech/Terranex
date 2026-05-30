/**
 * Seed data for development/demo.
 * Call seedDemoData() from browser console or a dev-only button.
 * Safe to call multiple times — checks if data already exists.
 */

import { projectsStore } from '../../features/projects/storage';
import { transactionsStore } from '../../features/transactions/storage';
import { obligationsStore } from '../../features/obligations/storage';
import { partnersStore } from '../../features/partners/storage';
import { assetsStore } from '../../features/assets/storage';
import { documentsStore } from '../../features/documents/storage';

export function seedDemoData() {
  // Only seed if no projects exist
  if (projectsStore.getAll().length > 0) {
    console.log('Seed skipped — data already exists');
    return;
  }

  // Partners
  const gulf = partnersStore.create({ name_ar: 'شركة البناء الخليجي', category: 'counterparty', counterparty_role: 'supplier' });
  const raidat = partnersStore.create({ name_ar: 'مجموعة الرواد', category: 'counterparty', counterparty_role: 'client' });
  const feed = partnersStore.create({ name_ar: 'شركة الأعلاف الخليجية', category: 'counterparty', counterparty_role: 'supplier' });
  const coop = partnersStore.create({ name_ar: 'تعاونية المزارعين', category: 'counterparty', counterparty_role: 'client' });
  const investor = partnersStore.create({ name_ar: 'محمد الرشيدي', category: 'equity_partner' });

  // Projects
  const prj1 = projectsStore.create({ name_ar: 'أرض المرسى', name_en: 'Al-Marsa Land', sector_id: 'real-estate', status: 'active', start_date: '2024-01-15', base_currency: 'EGP', description_ar: 'قطعة أرض بمساحة 5000 م² في موقع متميز.' });
  const prj2 = projectsStore.create({ name_ar: 'مزرعة الوادي', name_en: 'Al-Wadi Farm', sector_id: 'agriculture', status: 'active', start_date: '2024-03-01', base_currency: 'EGP', description_ar: 'موسم قمح — الربيع 2025.' });
  const prj3 = projectsStore.create({ name_ar: 'قطيع أبقار الجبل', name_en: 'Mountain Cattle Herd', sector_id: 'livestock', status: 'active', start_date: '2024-06-01', base_currency: 'EGP', description_ar: '80 رأس أبقار.' });
  const prj4 = projectsStore.create({ name_ar: 'برج الاستثمار', name_en: 'Investment Tower', sector_id: 'real-estate', status: 'planning', start_date: '2025-01-01', base_currency: 'EGP', description_ar: 'مشروع مبنى سكني من 12 طابق.' });

  // Assets
  assetsStore.create({ project_id: prj1.id, sector_id: 'real-estate', type: 'land', name_ar: 'قطعة أرض المرسى', name_en: 'Al-Marsa Plot', acquisition_date: '2024-01-15', acquisition_cost: 500000, acquisition_currency: 'EGP', acquisition_cost_egp: 500000, current_value_egp: 750000, status: 'owned' });
  assetsStore.create({ project_id: prj2.id, sector_id: 'agriculture', type: 'farm', name_ar: 'مزرعة الوادي', name_en: 'Wadi Farm', acquisition_date: '2024-03-01', acquisition_cost: 120000, acquisition_currency: 'EGP', acquisition_cost_egp: 120000, status: 'owned', quantity: 50, unit: 'فدان' });
  assetsStore.create({ project_id: prj3.id, sector_id: 'livestock', type: 'herd', name_ar: 'قطيع أبقار الجبل', name_en: 'Mountain Cattle', acquisition_date: '2024-06-01', acquisition_cost: 400000, acquisition_currency: 'EGP', acquisition_cost_egp: 400000, status: 'owned', quantity: 80, unit: 'رأس' });

  // Documents
  const doc1 = documentsStore.create({ project_id: prj1.id, type: 'ownership_deed', title_ar: 'صك ملكية أرض المرسى', issue_date: '2024-01-20' });
  const doc2 = documentsStore.create({ project_id: prj1.id, type: 'contract', title_ar: 'عقد التطوير مع البناء الخليجي', partner_id: gulf.id, issue_date: '2024-02-01' });
  const inv1 = documentsStore.create({ project_id: prj1.id, type: 'invoice', title_ar: 'فاتورة التطوير INV-2024-001', partner_id: gulf.id, issue_date: '2024-04-01' });
  const inv2 = documentsStore.create({ project_id: prj3.id, type: 'invoice', title_ar: 'فاتورة أعلاف INV-2024-091', partner_id: feed.id, issue_date: '2024-07-01' });

  const now = new Date();
  function d(monthsAgo: number) {
    const dt = new Date(now);
    dt.setMonth(dt.getMonth() - monthsAgo);
    return dt.toISOString().slice(0, 10);
  }

  // Transactions — project 1 (real estate)
  transactionsStore.create({ project_id: prj1.id, direction: 'expense', category: 'acquisition', amount: 500000, currency: 'EGP', fx_rate: 1, amount_egp: 500000, transaction_date: d(10), partner_id: raidat.id, document_id: doc1.id, description: 'تكلفة شراء الأرض' });
  transactionsStore.create({ project_id: prj1.id, direction: 'expense', category: 'development_cost', amount: 85000, currency: 'EGP', fx_rate: 1, amount_egp: 85000, transaction_date: d(7), partner_id: gulf.id, document_id: inv1.id, description: 'تطوير البنية التحتية' });
  transactionsStore.create({ project_id: prj1.id, direction: 'expense', category: 'legal_fee', amount: 12000, currency: 'EGP', fx_rate: 1, amount_egp: 12000, transaction_date: d(6), description: 'رسوم قانونية وتوثيق' });
  transactionsStore.create({ project_id: prj1.id, direction: 'income', category: 'sale', amount: 750000, currency: 'EGP', fx_rate: 1, amount_egp: 750000, transaction_date: d(2), partner_id: raidat.id, description: 'بيع جزء من الأرض' });
  transactionsStore.create({ project_id: prj1.id, direction: 'income', category: 'other', amount: 45000, currency: 'EGP', fx_rate: 1, amount_egp: 45000, transaction_date: d(1), description: 'إيجار مستودع' });

  // Transactions — project 2 (agriculture)
  transactionsStore.create({ project_id: prj2.id, direction: 'expense', category: 'seed_input', amount: 15000, currency: 'EGP', fx_rate: 1, amount_egp: 15000, transaction_date: d(5), description: 'بذور قمح' });
  transactionsStore.create({ project_id: prj2.id, direction: 'expense', category: 'fertilizer', amount: 22000, currency: 'EGP', fx_rate: 1, amount_egp: 22000, transaction_date: d(4), description: 'أسمدة الموسم' });
  transactionsStore.create({ project_id: prj2.id, direction: 'expense', category: 'irrigation', amount: 8000, currency: 'EGP', fx_rate: 1, amount_egp: 8000, transaction_date: d(3), description: 'تشغيل نظام الري' });
  transactionsStore.create({ project_id: prj2.id, direction: 'income', category: 'harvest_revenue', amount: 120000, currency: 'EGP', fx_rate: 1, amount_egp: 120000, transaction_date: d(1), partner_id: coop.id, description: 'مبيعات القمح للتعاونية' });

  // Transactions — project 3 (livestock)
  transactionsStore.create({ project_id: prj3.id, direction: 'expense', category: 'livestock_purchase', amount: 400000, currency: 'EGP', fx_rate: 1, amount_egp: 400000, transaction_date: d(8), description: 'شراء 80 رأس أبقار' });
  transactionsStore.create({ project_id: prj3.id, direction: 'expense', category: 'feed', amount: 8000, currency: 'EGP', fx_rate: 1, amount_egp: 8000, transaction_date: d(3), partner_id: feed.id, document_id: inv2.id, description: 'أعلاف شهر مارس' });
  transactionsStore.create({ project_id: prj3.id, direction: 'expense', category: 'feed', amount: 8000, currency: 'EGP', fx_rate: 1, amount_egp: 8000, transaction_date: d(2), partner_id: feed.id, description: 'أعلاف شهر أبريل' });
  transactionsStore.create({ project_id: prj3.id, direction: 'expense', category: 'veterinary', amount: 4500, currency: 'EGP', fx_rate: 1, amount_egp: 4500, transaction_date: d(2), description: 'كشف بيطري + علاج' });
  transactionsStore.create({ project_id: prj3.id, direction: 'expense', category: 'vaccination', amount: 2200, currency: 'EGP', fx_rate: 1, amount_egp: 2200, transaction_date: d(1), description: 'تحصينات دورية' });
  transactionsStore.create({ project_id: prj3.id, direction: 'income', category: 'livestock_sale', amount: 95000, currency: 'EGP', fx_rate: 1, amount_egp: 95000, transaction_date: d(1), description: 'بيع 19 رأس' });

  // Obligations
  const futureDate = (days: number) => new Date(Date.now() + days * 86400000).toISOString().slice(0, 10);
  const pastDate = (days: number) => new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);

  obligationsStore.create({ direction: 'receivable', partner_id: raidat.id, project_id: prj1.id, amount: 200000, currency: 'EGP', amount_egp: 200000, due_date: pastDate(15), status: 'open', notes: 'دفعة مؤجلة من مجموعة الرواد' });
  obligationsStore.create({ direction: 'payable', partner_id: gulf.id, project_id: prj1.id, amount: 45000, currency: 'EGP', amount_egp: 45000, due_date: futureDate(10), status: 'open', notes: 'الدفعة الأخيرة لعقد التطوير' });
  obligationsStore.create({ direction: 'receivable', partner_id: coop.id, project_id: prj2.id, amount: 30000, currency: 'EGP', amount_egp: 30000, due_date: futureDate(20), status: 'open' });
  obligationsStore.create({ direction: 'payable', partner_id: feed.id, project_id: prj3.id, amount: 8000, currency: 'EGP', amount_egp: 8000, due_date: pastDate(5), status: 'open', notes: 'فاتورة الأعلاف INV-2024-091' });

  console.log('✓ Demo data seeded successfully!');
}

// Expose globally for dev console
if (typeof window !== 'undefined') {
  (window as any).seedTerranexDemo = seedDemoData;
}
