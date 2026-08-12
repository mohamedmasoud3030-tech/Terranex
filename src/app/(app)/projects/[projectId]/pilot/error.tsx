'use client';

export default function PilotError({reset}:{error:Error&{digest?:string};reset:()=>void}){return <section className="card stack" role="alert"><h1>تعذر تحميل لوحة التشغيل التجريبي</h1><p className="error">لم نعرض مجاميع رقابة أو فروق مطابقة قديمة بدلًا من البيانات الحالية. تحقق من الاتصال والصلاحية ثم أعد المحاولة.</p><button onClick={()=>reset()}>إعادة المحاولة</button></section>;}
