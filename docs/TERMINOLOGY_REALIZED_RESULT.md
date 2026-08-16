# Terranex — Realized-Result / Result Terminology Matrix

**Status:** canonical terminology reference (corrective engineering)
**Date:** 2026-08-16
**Rule:** same label → same meaning; different meaning → different label.

This matrix documents the distinct financial measures that previously shared the
label "realized result" (or «النتيجة المحققة») so that no reader collapses unlike
accounting concepts into one number. None of these measures is an
**allocable investor result** — that remains policy-dependent (BD-006/007 OPEN).

| Canonical label | Arabic label | Source / view | Definition | Policy status |
|---|---|---|---|---|
| **Project recognized revenue** | الإيراد المعترف به | `project_financial_position_read.revenue_recognized_minor_units` (F9) | Sum of posted `REAL_ESTATE_SALE_REVENUE` + `REAL_ESTATE_RENTAL_REVENUE` + `AGRICULTURE_SALE_REVENUE` + `LIVESTOCK_SALE_REVENUE` (credits − debits). | policy-independent (management fact) |
| **Project cost of sale** | تكلفة البيع | `project_financial_position_read.cost_of_sale_minor_units` | Posted `REAL_ESTATE_COST_OF_SALE` (debits − credits). | policy-independent |
| **Project posted expense** | المصروف المرحَّل | `project_financial_position_read.expense_posted_minor_units` | Posted `PROJECT_EXPENSE` (debits − credits). | policy-independent |
| **Project work-in-progress** | أعمال تحت التنفيذ | `project_financial_position_read.wip_posted_minor_units` | Posted `DEVELOPMENT_WIP`. | policy-independent |
| **Real Estate sale realized result** | نتيجة البيع العقاري المحققة | `property_realized_result_read.realized_result_minor_units` (S4) | Real Estate sale revenue − carrying cost derecognized − selling costs. | policy-independent (per-property management fact) |
| **S5 allocable source (historical)** | مصدر التخصيص التاريخي (بيع عقاري فقط) | `s5_realized_result_as_of_snapshot` (read-labeled Real Estate sale only) | Real Estate sale revenue − cost of sale − SELLING expense, as-of a closed S6 snapshot. | policy-inert (BD-006 OPEN); RE-sale only, NOT a universal project result |
| **S5 technical capacity bridge (historical)** | جسر القدرة الفنية التاريخي | `s5_distribution_capacity_read.technical_capacity_bridge_minor_units` (formerly `distributable_cash_minor_units`) | max(0, BANK_CASH − positive SUPPLIER_PAYABLE − positive DISTRIBUTION_PAYABLE). | policy-inert (BD-008 OPEN); NOT company distributable cash |
| **S7 reconciliation checkpoint "REALIZED_RESULT"** | نقطة مطابقة النتيجة المحققة | `s7_reconciliation_checkpoints` checkpoint_code `REALIZED_RESULT` | External signed value vs Terranex-derived value, management reconciliation only. | policy-independent (reconciliation fact) |
| **Approved management valuation** | التقييم الإداري المعتمد | `property_valuations` / sector reads | Approved fair-value facts; management information only. | management info; never allocable/distributable (BD-007 OPEN) |
| **Allocable contractual result** | النتيجة التعاقدية القابلة للتخصيص | (does not exist yet) | A complete, professionally-defined allocable-result taxonomy per agreement. | R15/R16 policy-dependent; NOT implemented |

## Notes

- The F9 `project_performance_read` deliberately provides Revenue / Cost of Sale /
  Expense / WIP as **separate columns** — there is no single ambiguous "profit"
  number, and none is automatically allocable.
- The R8 cross-sector performance read exposes a per-asset/per-project realized
  result for management reporting; it is **not** an investor-allocation basis.
- The S5 source is read-labeled (COMMENT ON FUNCTION/COLUMN) because it derives
  only Real Estate sale facts; it must never be read as a universal Project
  realized result.
