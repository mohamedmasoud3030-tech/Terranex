import { useEffect, useState, type FormEvent } from 'react';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { FormError, FormField, FormLabel, SelectInput, TextInput, TextArea } from '../../components/ui/FormControls';
import type { CompanySettings, Currency } from '../../core/types/domain';
import { requireClient } from '../../core/storage/supabaseClientRegistry';
import { translateServerError } from '../../core/lib/serverErrorTranslator';

const CURRENCIES: Currency[] = ['EGP', 'USD', 'OMR', 'SAR', 'AED', 'EUR', 'GBP'];
const COUNTRIES: Array<{ code: CompanySettings['country']; label_ar: string; currency: Currency }> = [
  { code: 'EG', label_ar: 'مصر', currency: 'EGP' },
  { code: 'OM', label_ar: 'سلطنة عُمان', currency: 'OMR' },
  { code: 'SA', label_ar: 'السعودية', currency: 'SAR' },
  { code: 'AE', label_ar: 'الإمارات', currency: 'AED' },
  { code: 'OTHER', label_ar: 'بلد آخر', currency: 'USD' },
];

export function CompanySettingsForm() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const [nameAr, setNameAr] = useState('');
  const [nameEn, setNameEn] = useState('');
  const [commercialRegister, setCommercialRegister] = useState('');
  const [taxNumber, setTaxNumber] = useState('');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [address, setAddress] = useState('');
  const [city, setCity] = useState('');
  const [country, setCountry] = useState<CompanySettings['country']>('EG');
  const [baseCurrency, setBaseCurrency] = useState<Currency>('EGP');
  const [fiscalYearStart, setFiscalYearStart] = useState('');
  const [vatEnabled, setVatEnabled] = useState(false);
  const [vatRate, setVatRate] = useState('0');
  const [vatNumber, setVatNumber] = useState('');
  const [odooEnabled, setOdooEnabled] = useState(false);
  const [odooUrl, setOdooUrl] = useState('');
  const [odooDb, setOdooDb] = useState('');
  const [odooUsername, setOdooUsername] = useState('');
  const [etaBranchCode, setEtaBranchCode] = useState('0');

  useEffect(() => { void load(); }, []);

  async function load() {
    setLoading(true);
    try {
      const supabase = requireClient();
      const { data, error } = await supabase.from('company_settings').select('*').maybeSingle();
      if (error) throw error;
      if (data) {
        setNameAr(data.company_name_ar ?? '');
        setNameEn(data.company_name_en ?? '');
        setCommercialRegister(data.commercial_register ?? '');
        setTaxNumber(data.tax_number ?? '');
        setPhone(data.phone ?? '');
        setEmail(data.email ?? '');
        setAddress(data.address ?? '');
        setCity(data.city ?? '');
        setCountry(data.country ?? 'EG');
        setBaseCurrency(data.base_currency ?? 'EGP');
        setFiscalYearStart(data.fiscal_year_start ?? new Date().toISOString().slice(0, 10));
        setVatEnabled(data.vat_enabled ?? false);
        setVatRate(String(data.vat_rate ?? 0));
        setVatNumber(data.vat_number ?? '');
        setOdooEnabled(data.odoo_enabled ?? false);
        setOdooUrl(data.odoo_url ?? '');
        setOdooDb(data.odoo_db ?? '');
        setOdooUsername(data.odoo_username ?? '');
        setEtaBranchCode(data.eta_branch_code ?? '0');
      } else {
        setFiscalYearStart(new Date().toISOString().slice(0, 10));
      }
    } catch (e) { setError(translateServerError(e)); }
    finally { setLoading(false); }
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(''); setSuccess(''); setSaving(true);
    try {
      if (nameAr.trim().length < 2) throw new Error('اسم الشركة مطلوب.');
      const rate = Number(vatRate);
      if (!Number.isFinite(rate) || rate < 0 || rate > 100) throw new Error('نسبة الضريبة غير صالحة (0–100).');
      if (odooEnabled && (country !== 'EG' || baseCurrency !== 'EGP')) {
        throw new Error('مرحلة ربط Odoo الحالية مخصصة لمصر ويجب أن تكون العملة الأساس EGP.');
      }
      if (odooEnabled && !etaBranchCode.trim()) throw new Error('كود فرع الضرائب المصرية مطلوب. استخدم 0 عند وجود فرع واحد.');

      const supabase = requireClient();
      const values = {
        company_name_ar: nameAr.trim(),
        company_name_en: nameEn.trim() || null,
        commercial_register: commercialRegister.trim() || null,
        tax_number: taxNumber.trim() || null,
        phone: phone.trim() || null,
        email: email.trim() || null,
        address: address.trim() || null,
        city: city.trim() || null,
        country,
        base_currency: baseCurrency,
        fiscal_year_start: fiscalYearStart,
        vat_enabled: vatEnabled,
        vat_rate: rate,
        vat_number: vatNumber.trim() || null,
        odoo_enabled: odooEnabled,
        odoo_url: odooUrl.trim() || null,
        odoo_db: odooDb.trim() || null,
        odoo_username: odooUsername.trim() || null,
        odoo_localization: 'l10n_eg',
        eta_branch_code: etaBranchCode.trim() || '0',
        // ODOO_API_KEY is a server-side secret and is never written here.
      };
      const { data, error } = await supabase.from('company_settings').select('owner_id').maybeSingle();
      if (error) throw error;
      if (data) {
        const { error: updErr } = await supabase.from('company_settings').update(values).eq('owner_id', data.owner_id);
        if (updErr) throw updErr;
      } else {
        const { error: insErr } = await supabase.from('company_settings').insert(values);
        if (insErr) throw insErr;
      }
      setSuccess('تم حفظ إعدادات الشركة المصرية بنجاح.');
      setTimeout(() => setSuccess(''), 3000);
    } catch (e) { setError(translateServerError(e)); }
    finally { setSaving(false); }
  }

  if (loading) return <p className="text-sm text-muted-foreground">جارٍ تحميل الإعدادات…</p>;

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <Card>
        <CardHeader><span className="text-sm font-semibold">بيانات الشركة الأساسية</span></CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
            <FormField>
              <FormLabel>اسم الشركة (عربي)</FormLabel>
              <TextInput value={nameAr} onChange={e => setNameAr(e.target.value)} placeholder="شركة … للاستثمار" />
            </FormField>
            <FormField>
              <FormLabel>اسم الشركة (إنجليزي — اختياري)</FormLabel>
              <TextInput value={nameEn} onChange={e => setNameEn(e.target.value)} dir="ltr" />
            </FormField>
            <FormField>
              <FormLabel>الدولة</FormLabel>
              <SelectInput value={country} onChange={e => {
                const nextCountry = e.target.value as CompanySettings['country'];
                setCountry(nextCountry);
                const preset = COUNTRIES.find(item => item.code === nextCountry);
                if (preset) setBaseCurrency(preset.currency);
              }}>
                {COUNTRIES.map(item => <option key={item.code} value={item.code}>{item.label_ar}</option>)}
              </SelectInput>
            </FormField>
            <FormField>
              <FormLabel>المدينة</FormLabel>
              <TextInput value={city} onChange={e => setCity(e.target.value)} placeholder="القاهرة / الإسكندرية / الجيزة…" />
            </FormField>
            <FormField>
              <FormLabel>العملة الأساس</FormLabel>
              <SelectInput value={baseCurrency} onChange={e => setBaseCurrency(e.target.value as Currency)}>
                {CURRENCIES.map(code => <option key={code} value={code}>{code}</option>)}
              </SelectInput>
            </FormField>
            <FormField>
              <FormLabel>بداية السنة المالية</FormLabel>
              <TextInput type="date" value={fiscalYearStart} onChange={e => setFiscalYearStart(e.target.value)} />
            </FormField>
            <FormField>
              <FormLabel>السجل التجاري</FormLabel>
              <TextInput value={commercialRegister} onChange={e => setCommercialRegister(e.target.value)} dir="ltr" />
            </FormField>
            <FormField>
              <FormLabel>رقم التسجيل الضريبي</FormLabel>
              <TextInput value={taxNumber} onChange={e => setTaxNumber(e.target.value)} dir="ltr" />
            </FormField>
            <FormField>
              <FormLabel>الهاتف</FormLabel>
              <TextInput value={phone} onChange={e => setPhone(e.target.value)} dir="ltr" />
            </FormField>
            <FormField>
              <FormLabel>البريد الإلكتروني</FormLabel>
              <TextInput type="email" value={email} onChange={e => setEmail(e.target.value)} dir="ltr" />
            </FormField>
          </div>
          <FormField>
            <FormLabel>العنوان</FormLabel>
            <TextArea rows={2} value={address} onChange={e => setAddress(e.target.value)} />
          </FormField>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><span className="text-sm font-semibold">ضريبة القيمة المضافة</span></CardHeader>
        <CardContent className="space-y-3">
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={vatEnabled} onChange={e => setVatEnabled(e.target.checked)} />
            تفعيل ضريبة القيمة المضافة
          </label>
          {vatEnabled && (
            <div className="grid grid-cols-2 gap-3">
              <FormField>
                <FormLabel>نسبة الضريبة %</FormLabel>
                <TextInput type="number" min="0" max="100" step="0.5" value={vatRate} onChange={e => setVatRate(e.target.value)} />
              </FormField>
              <FormField>
                <FormLabel>رقم التسجيل الضريبي</FormLabel>
                <TextInput value={vatNumber} onChange={e => setVatNumber(e.target.value)} dir="ltr" />
              </FormField>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><span className="text-sm font-semibold">المحاسبة المصرية عبر Odoo 18</span></CardHeader>
        <CardContent className="space-y-3">
          <p className="text-xs text-muted-foreground">
            تستخدم المرحلة الحالية الحزمة المصرية <code>l10n_eg</code>. تتم مزامنة الشركاء والمشروعات
            والفواتير الصادرة أو المعتمدة من خلال Supabase Edge Function، ولا يصل مفتاح Odoo إلى المتصفح.
            ربط المدفوعات وETA الإلكتروني يأتي في المرحلة التالية ولا يُدّعى تشغيله الآن.
          </p>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={odooEnabled} onChange={e => setOdooEnabled(e.target.checked)} />
            تفعيل بوابة Odoo الآمنة
          </label>
          {odooEnabled && (
            <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
              <FormField>
                <FormLabel>رابط Odoo المرجعي</FormLabel>
                <TextInput value={odooUrl} onChange={e => setOdooUrl(e.target.value)} placeholder="https://odoo.example.com" dir="ltr" />
              </FormField>
              <FormField>
                <FormLabel>اسم قاعدة البيانات</FormLabel>
                <TextInput value={odooDb} onChange={e => setOdooDb(e.target.value)} placeholder="terranex_egypt" dir="ltr" />
              </FormField>
              <FormField>
                <FormLabel>اسم مستخدم التكامل</FormLabel>
                <TextInput value={odooUsername} onChange={e => setOdooUsername(e.target.value)} dir="ltr" />
              </FormField>
              <FormField>
                <FormLabel>كود فرع ETA</FormLabel>
                <TextInput value={etaBranchCode} onChange={e => setEtaBranchCode(e.target.value)} placeholder="0" dir="ltr" />
              </FormField>
              <FormField className="md:col-span-2">
                <FormLabel>مفتاح Odoo API</FormLabel>
                <p className="text-xs text-muted-foreground">
                  يُضبط على الخادم باسم <code>ODOO_API_KEY</code> كـ server-side secret داخل أسرار Supabase Edge Functions فقط.
                  لا تضعه في Vite أو قاعدة البيانات أو GitHub.
                </p>
              </FormField>
            </div>
          )}
        </CardContent>
      </Card>

      {error && <FormError>{error}</FormError>}
      {success && <div className="rounded-xl bg-emerald-500/10 border border-emerald-500/30 px-4 py-2 text-sm text-emerald-600">{success}</div>}
      <div className="flex gap-2">
        <Button type="submit" variant="primary" size="sm" disabled={saving}>{saving ? 'جارٍ الحفظ…' : 'حفظ الإعدادات'}</Button>
      </div>
    </form>
  );
}
