# XF-001: Month-End Close Checklist

## Metadata

| Field              | Value                                              |
|--------------------|----------------------------------------------------|
| **Document ID**    | XF-001                                             |
| **Domain**         | Cross-Functional (P2P + R2R)                       |
| **Category**       | Process Checklist                                  |
| **Created**        | 2026-02-14                                         |
| **Last Updated**   | 2026-02-14                                         |
| **Author**         | [Consultant Name]                                  |
| **Reviewed By**    | [Reviewer Name]                                    |
| **Version**        | 1.0                                                |

---

## Purpose

This checklist defines the month-end close process for the self-storage client, covering both P2P (Procure-to-Pay) and R2R (Record-to-Report) activities. The close runs over 5 business days following the last calendar day of each month. All 4 consultants participate: P2P tasks are handled by the P2P-assigned consultants, R2R tasks by the R2R-assigned consultants, and cross-functional tasks require coordination between both.

---

## Close Calendar

| Day             | Focus Area                              | Primary Team |
|-----------------|-----------------------------------------|--------------|
| **Day 1** (BD+1) | Cut-off, Open Items, Goods Receipt     | P2P          |
| **Day 2** (BD+2) | GR/IR Clearing, Accruals               | P2P + R2R    |
| **Day 3** (BD+3) | Depreciation, Revaluation, Allocations | R2R          |
| **Day 4** (BD+4) | Reconciliation and Review              | R2R + P2P    |
| **Day 5** (BD+5) | Reporting, Period Close, Sign-Off      | R2R          |

> **BD+N** = N business days after the last calendar day of the month.

---

## Day 1: Cut-Off and Open Items (P2P Focus)

**Objective:** Establish clean cut-off for the period. Ensure all received goods and services are recorded.

| # | Task                                          | Owner  | Fiori App / Transaction           | SOP Reference     | Status |
|---|-----------------------------------------------|--------|-----------------------------------|--------------------|--------|
| 1.1 | Send cut-off notification to client stakeholders | P2P | Email / Teams                    | --                 | [ ]    |
| 1.2 | Post all outstanding goods receipts for the period | P2P | Post Goods Receipt (F0843)     | SOP-P2P-003        | [ ]    |
| 1.3 | Review open purchase orders without GR        | P2P    | Manage Purchase Orders (F0843)   | SOP-P2P-005        | [ ]    |
| 1.4 | Identify POs with goods received but no invoice | P2P  | GR/IR Monitor                    | TS-P2P-001         | [ ]    |
| 1.5 | Process all vendor invoices received by cut-off | P2P  | Create Supplier Invoice (F0859)  | SOP-P2P-004        | [ ]    |
| 1.6 | Review and release blocked invoices           | P2P    | Manage Supplier Invoices (F0860) | SOP-P2P-006        | [ ]    |
| 1.7 | Review open purchase requisitions -- close or convert | P2P | Manage Purchase Requisitions (F1110) | SOP-P2P-007 | [ ]    |

**Day 1 Gate Check:**
- [ ] All goods receipts for the period are posted.
- [ ] All available vendor invoices are entered.
- [ ] Open PO list is reviewed and documented.

---

## Day 2: GR/IR Clearing and Accruals (P2P + R2R)

**Objective:** Clear the GR/IR account, post accruals for uninvoiced receipts, and record other period-end accruals.

| # | Task                                          | Owner  | Fiori App / Transaction           | SOP Reference     | Status |
|---|-----------------------------------------------|--------|-----------------------------------|--------------------|--------|
| 2.1 | Run GR/IR clearing program                   | P2P    | Automatic GR/IR Clearing          | TS-P2P-001         | [ ]    |
| 2.2 | Review GR/IR clearing exceptions             | P2P    | GR/IR Account Analysis            | TS-P2P-001         | [ ]    |
| 2.3 | Post accruals for goods received / not invoiced | R2R  | Manage Journal Entries (F2548)    | SOP-R2R-001        | [ ]    |
| 2.4 | Post accruals for services performed / not invoiced | R2R | Manage Journal Entries (F2548) | SOP-R2R-001        | [ ]    |
| 2.5 | Post recurring accruals (rent, insurance, utilities) | R2R | Manage Journal Entries (F2548) | SOP-R2R-005        | [ ]    |
| 2.6 | Reverse prior month accruals                 | R2R    | Manage Journal Entries (F2548)    | SOP-R2R-002        | [ ]    |
| 2.7 | Post payroll accruals (if provided by client) | R2R   | Manage Journal Entries (F2548)    | SOP-R2R-001        | [ ]    |
| 2.8 | Review vendor aging report for completeness  | P2P    | Supplier Balances (F0710)         | --                 | [ ]    |

**Day 2 Gate Check:**
- [ ] GR/IR clearing completed; exceptions documented.
- [ ] All accruals posted with supporting documentation attached.
- [ ] Prior month accruals reversed.
- [ ] Vendor aging reviewed -- no unexpected open items.

---

## Day 3: Depreciation, Revaluation, and Allocations (R2R Focus)

**Objective:** Run automated period-end postings and allocations.

| # | Task                                          | Owner  | Fiori App / Transaction           | SOP Reference     | Status |
|---|-----------------------------------------------|--------|-----------------------------------|--------------------|--------|
| 3.1 | Run fixed asset depreciation                 | R2R    | Run Depreciation (F2667)          | SOP-R2R-003        | [ ]    |
| 3.2 | Review depreciation run log for errors       | R2R    | Depreciation Run Log              | SOP-R2R-003        | [ ]    |
| 3.3 | Post manual depreciation adjustments (if any) | R2R   | Manage Journal Entries (F2548)    | SOP-R2R-001        | [ ]    |
| 3.4 | Run foreign currency revaluation (if applicable) | R2R | Manage Foreign Currency Revaluation | SOP-R2R-004     | [ ]    |
| 3.5 | Post intercompany cost allocations           | R2R    | Manage Journal Entries (F2548)    | SOP-R2R-001        | [ ]    |
| 3.6 | Run overhead cost allocation (if configured) | R2R    | Allocations Management            | CFG-R2R-003        | [ ]    |
| 3.7 | Post tax-related adjustments (if any)        | R2R    | Manage Journal Entries (F2548)    | SOP-R2R-001        | [ ]    |

**Day 3 Gate Check:**
- [ ] Depreciation run completed without errors.
- [ ] FX revaluation completed (if applicable for the period).
- [ ] All intercompany allocations posted and balanced.
- [ ] Overhead allocations completed.

---

## Day 4: Reconciliation and Review (Cross-Functional)

**Objective:** Reconcile all sub-ledgers to the general ledger. Identify and resolve discrepancies.

| # | Task                                          | Owner  | Fiori App / Transaction           | SOP Reference     | Status |
|---|-----------------------------------------------|--------|-----------------------------------|--------------------|--------|
| 4.1 | Reconcile AP sub-ledger to GL control account | P2P + R2R | Display Line Items (F0706)   | TS-R2R-002         | [ ]    |
| 4.2 | Reconcile fixed asset sub-ledger to GL       | R2R    | Asset History Sheet               | TS-R2R-003         | [ ]    |
| 4.3 | Reconcile bank accounts                      | R2R    | Manage Bank Statements (F1609)    | SOP-R2R-006        | [ ]    |
| 4.4 | Reconcile intercompany balances              | R2R    | Intercompany Reconciliation       | TS-R2R-004         | [ ]    |
| 4.5 | Review P&L by cost center -- investigate variances | R2R | Cost Center Reporting (F0712) | --                 | [ ]    |
| 4.6 | Review balance sheet for unusual balances    | R2R    | Trial Balance (F0708)             | --                 | [ ]    |
| 4.7 | Clear any remaining GR/IR differences        | P2P    | GR/IR Account Analysis            | TS-P2P-001         | [ ]    |
| 4.8 | Document all reconciliation results          | R2R    | Shared folder / Teams             | --                 | [ ]    |

**Day 4 Gate Check:**
- [ ] AP sub-ledger reconciles to GL within tolerance.
- [ ] Fixed asset sub-ledger reconciles to GL.
- [ ] Bank reconciliation completed -- no unreconciled items above threshold.
- [ ] Intercompany balances net to zero across all company codes.
- [ ] All reconciliation documentation saved.

---

## Day 5: Reporting, Period Close, and Sign-Off (R2R Focus)

**Objective:** Generate management reports, close the posting period, and obtain sign-off.

| # | Task                                          | Owner  | Fiori App / Transaction           | SOP Reference     | Status |
|---|-----------------------------------------------|--------|-----------------------------------|--------------------|--------|
| 5.1 | Generate trial balance for the closed period | R2R    | Trial Balance (F0708)             | --                 | [ ]    |
| 5.2 | Generate P&L statement                       | R2R    | Financial Statements (F0709)      | --                 | [ ]    |
| 5.3 | Generate balance sheet                       | R2R    | Financial Statements (F0709)      | --                 | [ ]    |
| 5.4 | Prepare management reporting package         | R2R    | Excel / PowerPoint                | --                 | [ ]    |
| 5.5 | Prepare variance analysis commentary         | R2R    | Excel / Teams                     | --                 | [ ]    |
| 5.6 | Close the posting period for P2P             | R2R    | Manage Posting Periods            | CFG-R2R-001        | [ ]    |
| 5.7 | Close the posting period for R2R             | R2R    | Manage Posting Periods            | CFG-R2R-001        | [ ]    |
| 5.8 | Send close completion notification to client | R2R    | Email / Teams                     | --                 | [ ]    |
| 5.9 | Obtain client sign-off on financial package  | R2R    | Email / Teams                     | --                 | [ ]    |
| 5.10 | Conduct internal close retrospective        | All    | Teams meeting                     | --                 | [ ]    |

**Day 5 Gate Check:**
- [ ] Financial statements generated and reviewed for accuracy.
- [ ] Management package distributed to client stakeholders.
- [ ] Posting periods closed for the completed month.
- [ ] Client sign-off received (or documented as pending with follow-up date).
- [ ] Retrospective notes captured for process improvement.

---

## Key Accounts to Monitor

| Account Description         | GL Account Range | What to Check                                |
|-----------------------------|------------------|----------------------------------------------|
| GR/IR Clearing              | 23XXXX           | Balance should be near zero after clearing   |
| AP Control                  | 21XXXX           | Must reconcile to AP sub-ledger              |
| Accrued Liabilities         | 22XXXX           | Prior month reversed; current month posted   |
| Fixed Assets                | 10XXXX-12XXXX    | Reconciles to asset sub-ledger               |
| Depreciation Expense        | 47XXXX           | Matches depreciation run output              |
| Intercompany Receivable     | 14XXXX           | Nets to zero across all company codes        |
| Intercompany Payable        | 24XXXX           | Nets to zero across all company codes        |
| Bank Accounts               | 11XXXX           | Reconciles to bank statements                |

> **Note:** Replace account ranges above with the actual GL account numbers from the client's chart of accounts (see `client-specific/system-landscape.md`).

---

## Escalation Contacts

| Issue                                    | Escalation To                      | Timeline    |
|------------------------------------------|------------------------------------|-------------|
| Posting period cannot be opened          | SAP Basis / System Admin           | Immediate   |
| GR/IR differences above threshold        | P2P Team Lead + Client Procurement | Day 2       |
| Depreciation run fails                   | R2R Team Lead                      | Day 3       |
| Reconciliation breaks above tolerance    | R2R Team Lead + Client Controller  | Day 4       |
| Client sign-off delayed                  | Engagement Manager                 | Day 5 + 1   |

---

## Timing and SLA

| Milestone                       | Target Completion | SLA         |
|---------------------------------|-------------------|-------------|
| All GRs and invoices posted     | Day 1 EOD         | Mandatory   |
| GR/IR cleared, accruals posted  | Day 2 EOD         | Mandatory   |
| Depreciation and allocations    | Day 3 EOD         | Mandatory   |
| Reconciliation completed        | Day 4 EOD         | Mandatory   |
| Financial package delivered     | Day 5 EOD         | Contractual |
| Client sign-off received        | Day 5 + 2         | Best effort |

---

## Change Log

| Version | Date       | Author           | Description                     |
|---------|------------|------------------|---------------------------------|
| 1.0     | 2026-02-14 | [Consultant Name] | Initial version created        |
