# SOP-P2P-001: Create Purchase Order in SAP S/4HANA Fiori

> **This document serves as the TEMPLATE for all SOPs in this knowledge base.**
> All new SOPs must follow this structure. See `knowledge-base/README.md` for guidelines.

---

## Metadata

| Field              | Value                                              |
|--------------------|----------------------------------------------------|
| **Document ID**    | SOP-P2P-001                                        |
| **Domain**         | P2P (Procure-to-Pay)                               |
| **Category**       | How-To                                             |
| **Fiori App**      | Create Purchase Order (F0842)                      |
| **SAP Role Required** | SAP_BR_PURCHASER (Purchaser)                    |
| **Created**        | 2026-02-14                                         |
| **Last Updated**   | 2026-02-14                                         |
| **Author**         | [Consultant Name]                                  |
| **Reviewed By**    | [Reviewer Name]                                    |
| **Version**        | 1.0                                                |

---

## Purpose

This SOP describes how to create a standard purchase order (PO) in SAP S/4HANA Public Cloud using the Fiori app "Create Purchase Order" (F0842). This is used when procurement of materials or services has been approved and a formal PO must be issued to the vendor. This is the most common purchasing transaction in the self-storage client's daily operations, covering facility maintenance supplies, packaging materials, and contracted services.

---

## Prerequisites

Before starting, confirm the following:

- [ ] You have the **SAP_BR_PURCHASER** business role assigned to your user.
- [ ] The **vendor (supplier)** exists in the system and is not blocked for purchasing.
- [ ] The **material or service** is maintained in the material master (for stock items) or will be entered as a free-text item (for non-stock items).
- [ ] A valid **purchase requisition** exists (if your process requires PO creation with reference to a PR).
- [ ] You know the correct **purchasing organization** and **purchasing group** for the transaction.
- [ ] The **company code** is confirmed (refer to `client-specific/system-landscape.md`).
- [ ] Budget availability has been confirmed with the R2R team if the order exceeds the threshold defined in the approval workflow.

---

## Step-by-Step Procedure

### Step 1: Navigate to the Fiori App

1. Open the SAP Fiori Launchpad in your browser.
2. In the search bar at the top of the Launchpad, type **"Create Purchase Order"**.
3. Click the **Create Purchase Order** tile (App ID: F0842).
   - Alternative navigation: **Purchasing** group > **Create Purchase Order**.

### Step 2: Enter Header Data

1. In the **Supplier** field, enter the vendor number or search by name using the value help (F4).
2. The **Purchasing Organization** will default based on your user settings. Verify it is correct:
   - For the self-storage client, use purchasing org **1000** (unless otherwise specified).
3. The **Purchasing Group** will default. Verify or change as needed.
4. **Company Code** should auto-populate. Confirm it matches the ordering entity.
5. Optionally enter a **Reference** number (e.g., an internal requisition number or email reference).

### Step 3: Add Line Items

1. In the **Items** section, click **Add Item** (or press the "+" icon).
2. For each line item, enter:

   | Field                  | Description                                                  |
   |------------------------|--------------------------------------------------------------|
   | **Material**           | Material number (for stock items) or leave blank for free text |
   | **Short Text**         | Description of the item or service                           |
   | **PO Quantity**        | Quantity to be ordered                                       |
   | **Order Unit**         | Unit of measure (EA, PC, HR, etc.)                           |
   | **Net Price**          | Price per unit (excluding tax)                               |
   | **Plant**              | Receiving plant (default: 1000)                              |
   | **Storage Location**   | Where goods will be received (if applicable)                 |
   | **Account Assignment** | Cost center, GL account, or WBS element                      |
   | **Delivery Date**      | Requested delivery date                                      |

3. For **service purchase orders** (e.g., contracted maintenance):
   - Select item category **D** (Service).
   - Enter service details in the **Service** tab of the line item.
   - Specify the **expected value** rather than quantity x price.

4. Repeat for additional line items.

### Step 4: Review Account Assignment

1. Click on a line item, then navigate to the **Account Assignment** tab.
2. Verify the following fields:

   | Field              | Typical Value for Self-Storage Client                  |
   |--------------------|--------------------------------------------------------|
   | **Cost Center**    | As defined per facility or department                  |
   | **GL Account**     | Auto-derived from material group or manually entered   |
   | **Profit Center**  | Auto-derived from cost center                          |

3. If the PO is for a capital item, ensure the account assignment category is set to **A** (Asset) and the asset number is entered.

### Step 5: Check Pricing and Conditions

1. Navigate to the **Conditions** tab at the line item level.
2. Verify the **gross price** (PBXX) is correct.
3. If applicable, check for:
   - Freight charges (FRA1)
   - Discounts (if contract pricing applies)
4. The **net value** displayed should match the agreed-upon amount with the vendor.

### Step 6: Add Notes and Attachments (Optional)

1. Navigate to the **Notes** tab to add:
   - **Item Text:** Printed on the PO sent to the vendor.
   - **Internal Note:** Visible only within SAP (not printed).
2. Use the **Attachments** section to upload supporting documents (quotes, approval emails).

### Step 7: Validate and Simulate

1. Click the **Check** button (or press Ctrl+Enter) to run validation.
2. Review any warning or error messages in the message bar at the bottom.
3. Address all errors before proceeding. Warnings can be reviewed and accepted if appropriate.

### Step 8: Save the Purchase Order

1. Click **Order** (or press Ctrl+S) to save and create the purchase order.
2. The system will display a confirmation message: **"Purchase Order [4500XXXXXX] created."**
3. **Record the PO number** for tracking purposes.

### Step 9: Output and Communication

1. If automatic output is configured, the PO will be sent to the vendor via the configured channel (email, EDI).
2. To manually trigger output:
   - Open the PO using "Manage Purchase Orders" (F0843).
   - Navigate to **Output** tab.
   - Click **Preview** to review the printed format.
   - Click **Send** to transmit.

---

## Validation and Verification

After creating the PO, verify the following:

| Check                              | How                                                       |
|------------------------------------|-----------------------------------------------------------|
| PO number generated                | Confirmation message on screen                            |
| PO status is "Ordered"             | Open in Manage Purchase Orders (F0843) and check status   |
| Correct vendor                     | Review header in PO display                               |
| Line items and quantities correct  | Review Items tab                                          |
| Pricing matches agreement          | Review Conditions tab per line item                       |
| Account assignment correct         | Review Account Assignment tab per line item               |
| Output sent to vendor              | Check Output tab -- status should show "Sent" or "Printed"|
| Budget not exceeded                | No budget warning messages (if budget checking is active) |

---

## Common Errors and Resolutions

| Error Message                                    | Root Cause                                           | Resolution                                                  |
|--------------------------------------------------|------------------------------------------------------|-------------------------------------------------------------|
| "Vendor XXXXXX is blocked for purchasing org"    | Vendor is blocked at purchasing org level             | Contact master data team to review and unblock vendor        |
| "Material XXXXXXXXX does not exist in plant"     | Material not extended to the relevant plant           | Request material extension via "Manage Product Master Data"  |
| "No source of supply found"                      | Source list or info record missing for the material   | Create a purchase info record or update the source list      |
| "Account assignment mandatory for item category"  | Account assignment category requires cost object      | Enter cost center, WBS element, or order number              |
| "Delivery date is in the past"                   | Requested delivery date is before today's date        | Update delivery date to a future date                        |
| "Price variance exceeds tolerance"               | Net price deviates from info record or contract price | Verify price with vendor; update info record if changed      |
| "Budget exceeded for cost center XXXXXXXXXX"     | PO value exceeds available budget                     | Contact R2R team to review budget availability               |
| "Purchasing group not valid for purchasing org"   | Mismatch between purchasing group and org             | Verify purchasing group assignment in org structure           |

---

## Tips for the Self-Storage Client

- **Facility Supplies:** Most POs for cleaning and maintenance supplies use material group **MG-MAINT**. The GL account defaults from the material group -- do not override unless instructed.
- **Contracted Services:** Use service POs (item category D) for recurring vendor contracts (pest control, security, HVAC). Reference the existing outline agreement number if applicable.
- **Approval Workflow:** POs above the configured threshold (check current threshold in `CFG-P2P-002-approval-workflow-config.md`) will route for approval. You will see status "Awaiting Approval" until the approver acts.
- **Blanket POs:** For recurring monthly services, consider creating a blanket PO with a total value limit and multiple delivery dates rather than monthly individual POs.

---

## Related SOPs

| Document ID   | Title                                        | Relevance                                    |
|---------------|----------------------------------------------|----------------------------------------------|
| SOP-P2P-002   | Create Purchase Order with Reference to PR   | When PO must reference an existing requisition |
| SOP-P2P-003   | Post Goods Receipt Against Purchase Order     | Next step after vendor delivers goods         |
| SOP-P2P-004   | Process Vendor Invoice                       | Invoice verification against PO               |
| SOP-P2P-005   | Manage Purchase Order Changes                | Modifying an existing PO                      |
| SOP-R2R-001   | Post Journal Entry                           | If manual accrual is needed for PO            |
| TS-P2P-001    | Resolve GR/IR Clearing Differences           | When goods receipt and invoice don't match    |
| CFG-P2P-001   | Purchasing Organization Configuration        | Org structure reference                       |

---

## Change Log

| Version | Date       | Author           | Description                     |
|---------|------------|------------------|---------------------------------|
| 1.0     | 2026-02-14 | [Consultant Name] | Initial version created        |
