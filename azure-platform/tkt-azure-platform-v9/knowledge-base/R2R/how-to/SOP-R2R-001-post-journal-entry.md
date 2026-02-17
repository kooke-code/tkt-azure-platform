# SOP-R2R-001: Post Journal Entry in SAP S/4HANA Fiori

---

## Metadata

| Field              | Value                                              |
|--------------------|----------------------------------------------------|
| **Document ID**    | SOP-R2R-001                                        |
| **Domain**         | R2R (Record-to-Report)                             |
| **Category**       | How-To                                             |
| **Fiori App**      | Manage Journal Entries (F2548)                     |
| **SAP Role Required** | SAP_BR_GL_ACCOUNTANT (General Ledger Accountant)|
| **Created**        | 2026-02-14                                         |
| **Last Updated**   | 2026-02-14                                         |
| **Author**         | [Consultant Name]                                  |
| **Reviewed By**    | [Reviewer Name]                                    |
| **Version**        | 1.0                                                |

---

## Purpose

This SOP describes how to post a manual journal entry (JE) in SAP S/4HANA Public Cloud using the Fiori app "Manage Journal Entries" (F2548). Manual journal entries are used for transactions that are not generated automatically by sub-ledger postings, including accruals, reclassifications, corrections, intercompany allocations, and other adjusting entries. For the self-storage client, common use cases include monthly rent accruals, depreciation adjustments, and intercompany cost allocations across facility company codes.

---

## Prerequisites

Before starting, confirm the following:

- [ ] You have the **SAP_BR_GL_ACCOUNTANT** business role assigned to your user.
- [ ] The **company code** for the posting is confirmed (refer to `client-specific/system-landscape.md`).
- [ ] The **posting period** is open for the target fiscal year/period. Check with the period-close administrator if unsure.
- [ ] You have the correct **GL accounts** for both the debit and credit sides of the entry.
- [ ] The journal entry has been **approved** per the client's authorization matrix (entries above the materiality threshold require documented approval before posting).
- [ ] Supporting documentation (calculation, approval email, spreadsheet) is ready to attach.
- [ ] For intercompany entries: the corresponding entry in the partner company code is planned and coordinated.

---

## Step-by-Step Procedure

### Step 1: Navigate to the Fiori App

1. Open the SAP Fiori Launchpad in your browser.
2. In the search bar, type **"Manage Journal Entries"**.
3. Click the **Manage Journal Entries** tile (App ID: F2548).
   - Alternative navigation: **Finance** group > **Manage Journal Entries**.
4. The app opens to the journal entry list view. Click **Create** (or the "+" icon) to start a new entry.

### Step 2: Enter Header Data

1. Complete the header fields:

   | Field                      | Description                                                  |
   |----------------------------|--------------------------------------------------------------|
   | **Company Code**           | Select the company code for this posting                     |
   | **Journal Entry Type**     | Select the appropriate type (see table below)                |
   | **Journal Entry Date**     | The accounting date for the posting (determines the period)  |
   | **Posting Date**           | Usually the same as journal entry date                       |
   | **Reference**              | External reference (e.g., "Feb-2026 Rent Accrual")           |
   | **Journal Entry Header Text** | Brief description visible in reports                     |
   | **Ledger Group**           | Leave as default (0L) for leading ledger postings            |

2. Common **Journal Entry Types** for the self-storage client:

   | Type Code | Description                    | When to Use                                      |
   |-----------|--------------------------------|--------------------------------------------------|
   | **SA**    | GL Account Document            | Standard manual postings, accruals, adjustments  |
   | **AA**    | Asset Accounting               | Depreciation adjustments, asset reclassification |
   | **AB**    | Clearing                       | Account clearing entries                         |

### Step 3: Enter Line Items

1. In the **Line Items** section, enter the debit and credit lines.
2. For each line item, complete:

   | Field                  | Description                                                  |
   |------------------------|--------------------------------------------------------------|
   | **GL Account**         | General ledger account number                                |
   | **Debit/Credit**       | Select D (Debit) or C (Credit) indicator                     |
   | **Amount in Doc. Currency** | Amount for this line (in document currency)             |
   | **Cost Center**        | Required for P&L accounts; assigned per facility/department  |
   | **Profit Center**      | Auto-derived from cost center; verify                        |
   | **Functional Area**    | Auto-derived if configured; verify for correct P&L mapping   |
   | **Assignment**         | Additional reference (e.g., facility code, invoice number)   |
   | **Item Text**          | Description for this specific line                           |

3. **Rules for balanced entries:**
   - The total debits must equal total credits within the journal entry.
   - The balance indicator at the bottom of the screen will show the difference -- this must be zero before posting.

4. **For intercompany entries:**
   - Enter the trading partner company code in the **Trading Partner** field on each line.
   - The system will auto-generate the offsetting intercompany receivable/payable if configured.

### Step 4: Handle Multi-Currency Postings (If Applicable)

1. If the journal entry involves a foreign currency:
   - Set the **Document Currency** in the header to the foreign currency (e.g., USD, EUR, GBP).
   - The system will translate to the local currency using the exchange rate valid on the posting date.
2. To override the exchange rate:
   - Enter the rate manually in the **Exchange Rate** field in the header.
   - Document the reason for the override in the header text.

### Step 5: Attach Supporting Documentation

1. Click the **Attachments** icon in the header area.
2. Upload the supporting document(s):
   - Approval email or signed form
   - Calculation spreadsheet
   - Source documentation (vendor statement, bank confirmation, etc.)
3. Best practice: every manual journal entry should have at least one attachment providing audit trail.

### Step 6: Validate the Entry

1. Click the **Check** button to run validation.
2. The system will check for:
   - Balanced debits and credits
   - Valid GL accounts and cost objects
   - Open posting period
   - Required field completeness
3. Review all messages:
   - **Errors (red):** Must be resolved before posting.
   - **Warnings (yellow):** Review and confirm they are acceptable.

### Step 7: Simulate (Recommended)

1. Click the **Simulate** button to preview the accounting document.
2. The simulation shows:
   - All line items as they will be posted
   - Currency translations
   - Derived fields (profit center, functional area)
   - Tax calculations (if applicable)
3. Verify the simulation matches your expected entry.

### Step 8: Post the Journal Entry

1. Click **Post** to create the accounting document.
2. The system will display: **"Journal Entry [XXXXXXXXXX] posted in company code [XXXX]."**
3. **Record the document number** for tracking and reconciliation.

### Step 9: Review the Posted Entry

1. The posted entry will appear in the journal entry list.
2. Click on the document number to review all details.
3. Verify the posting is reflected in the correct period by checking the fiscal year/period in the header.

---

## Validation and Verification

After posting the journal entry, verify the following:

| Check                                | How                                                       |
|--------------------------------------|-----------------------------------------------------------|
| Document number generated            | Confirmation message on screen                            |
| Debits equal credits                 | Review document -- balance must be zero                   |
| Correct posting period               | Check fiscal year/period in document header               |
| GL accounts correct                  | Review line items in document display                     |
| Cost center/profit center assigned   | Review account assignment fields per line                 |
| Entry visible in GL line items       | Use "Display Line Items in General Ledger" (F0706)        |
| Attachment present                   | Verify supporting document is attached                    |
| Intercompany partner balanced        | If applicable, verify partner entry in other company code |

---

## Common Errors and Resolutions

| Error Message                                        | Root Cause                                              | Resolution                                                  |
|------------------------------------------------------|---------------------------------------------------------|-------------------------------------------------------------|
| "Posting period [MM YYYY] is not open"               | Period is locked for the target date                    | Contact period admin to open the period, or adjust the posting date to an open period |
| "Balance in transaction currency is not zero"        | Debits and credits do not balance                       | Review line item amounts; correct the discrepancy           |
| "Cost center is required for account XXXXXXXX"       | P&L account requires cost center assignment             | Enter the appropriate cost center for each P&L line item    |
| "GL account XXXXXXXX does not exist in company code" | Account not created in the target company code          | Verify the GL account number; request account creation if needed |
| "Document type SA not allowed for account type"      | Mismatch between document type and account type posted  | Use the correct document type (e.g., AA for asset postings) |
| "Tax code required for line item"                    | GL account requires tax code but none was entered       | Enter the appropriate tax code (e.g., V0 for exempt)        |
| "Amount exceeds tolerance for user [USERNAME]"       | Posting amount exceeds user authorization limit         | Request a user with higher authorization to post, or split the entry if appropriate |
| "Profit center could not be derived"                 | Cost center has no profit center assignment              | Contact master data team to assign profit center to the cost center |

---

## Tips for the Self-Storage Client

- **Monthly Accruals:** Use a consistent reference format: `[Mon]-[Year] [Description] Accrual` (e.g., "Feb-2026 Rent Accrual"). This makes it easy to identify and reverse accruals.
- **Accrual Reversals:** When posting an accrual, immediately create the reversal entry for the following period using the **Reverse on** field in the header. Set the reversal date to Day 1 of the next period.
- **Depreciation Adjustments:** Depreciation should normally run automatically via the depreciation run. Only post manual depreciation entries if the automatic run produces incorrect results and after consulting with the team lead.
- **Intercompany Allocations:** The self-storage client allocates shared corporate costs across facility company codes monthly. Use document type SA with trading partner populated on every line. Coordinate with the P2P team to ensure the allocation basis is agreed before posting.
- **Recurring Entries:** For entries that repeat each month with the same accounts and amounts, consider setting up a recurring journal entry template within the app to reduce manual effort and errors.

---

## Related SOPs

| Document ID   | Title                                          | Relevance                                      |
|---------------|------------------------------------------------|------------------------------------------------|
| SOP-R2R-002   | Reverse a Journal Entry                        | Correcting or reversing a posted entry         |
| SOP-R2R-003   | Run Automatic Depreciation                     | Scheduled depreciation posting                 |
| SOP-R2R-004   | Perform Foreign Currency Revaluation           | Period-end FX adjustment                       |
| SOP-R2R-005   | Post Recurring Journal Entries                 | Automating monthly repeating entries           |
| SOP-P2P-004   | Process Vendor Invoice                         | When JE relates to accrued vendor liability    |
| TS-R2R-001    | Resolve Period Lock Issues                     | When posting period is unexpectedly closed     |
| XF-001        | Month-End Close Checklist                      | Where JE posting fits in the close process     |

---

## Change Log

| Version | Date       | Author           | Description                     |
|---------|------------|------------------|---------------------------------|
| 1.0     | 2026-02-14 | [Consultant Name] | Initial version created        |
