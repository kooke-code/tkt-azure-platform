# CS-001: Client System Landscape -- SAP S/4HANA Public Cloud

## Metadata

| Field              | Value                                              |
|--------------------|----------------------------------------------------|
| **Document ID**    | CS-001                                             |
| **Domain**         | Client-Specific                                    |
| **Category**       | System Documentation                               |
| **Classification** | Confidential -- Internal Use Only                  |
| **Created**        | 2026-02-14                                         |
| **Last Updated**   | 2026-02-14                                         |
| **Author**         | [Consultant Name]                                  |
| **Reviewed By**    | [Reviewer Name]                                    |
| **Version**        | 1.0                                                |

> **IMPORTANT:** This document contains client-specific system details. Do not share outside the TKT managed services team without client approval.

---

## 1. System URLs and Access

### SAP S/4HANA Public Cloud Tenant

| Environment    | Purpose               | Fiori Launchpad URL                              | API Endpoint                                      |
|----------------|-----------------------|--------------------------------------------------|---------------------------------------------------|
| **Production** | Live system           | `https://[tenant-id].s4hana.cloud.sap/ui`       | `https://[tenant-id].s4hana.cloud.sap/sap/opu/`  |
| **Quality**    | Testing and UAT       | `https://[tenant-id]-q.s4hana.cloud.sap/ui`     | `https://[tenant-id]-q.s4hana.cloud.sap/sap/opu/` |
| **Development**| Configuration changes | `https://[tenant-id]-d.s4hana.cloud.sap/ui`     | `https://[tenant-id]-d.s4hana.cloud.sap/sap/opu/` |

> Replace `[tenant-id]` with the actual SAP tenant identifier provided during onboarding.

### SAP Business Technology Platform (BTP)

| Component                 | URL                                                  |
|---------------------------|------------------------------------------------------|
| BTP Cockpit               | `https://cockpit.[region].hana.ondemand.com/`        |
| Identity Authentication   | `https://[tenant].accounts.ondemand.com/admin/`      |
| SAP Analytics Cloud (SAC) | `https://[tenant].us10.sapanalytics.cloud/`          |

### Other Systems

| System                    | URL / Access Method          | Purpose                          |
|---------------------------|------------------------------|----------------------------------|
| Azure Virtual Desktop     | Via Microsoft Remote Desktop | Consultant desktop environment   |
| Azure DevOps              | `https://dev.azure.com/[org]`| Project management and CI/CD     |
| Teams Channel             | [Link to Teams channel]      | Team communication               |
| SharePoint Document Store | [Link to SharePoint site]    | Client document repository       |

---

## 2. Company Codes

| Company Code | Company Name                        | Country | Currency | City            | Purpose                          |
|--------------|-------------------------------------|---------|----------|-----------------|----------------------------------|
| **1000**     | [Client Name] -- Corporate HQ      | US      | USD      | [City, State]   | Corporate / shared services      |
| **1100**     | [Client Name] -- Region East       | US      | USD      | [City, State]   | Eastern facilities operations    |
| **1200**     | [Client Name] -- Region West       | US      | USD      | [City, State]   | Western facilities operations    |
| **1300**     | [Client Name] -- Region Central    | US      | USD      | [City, State]   | Central facilities operations    |

> Update this table with the actual company codes after client onboarding.

---

## 3. Organizational Structure

### Procurement (P2P)

| Element               | Value     | Description                                   |
|-----------------------|-----------|-----------------------------------------------|
| **Purchasing Org**    | 1000      | Central purchasing organization               |
| **Purchasing Group**  | 001       | Facility maintenance procurement              |
| **Purchasing Group**  | 002       | Corporate procurement                         |
| **Purchasing Group**  | 003       | IT and services procurement                   |
| **Plant**             | 1000      | Corporate HQ / Central warehouse              |
| **Plant**             | 1100      | Regional East hub                             |
| **Plant**             | 1200      | Regional West hub                             |
| **Plant**             | 1300      | Regional Central hub                          |
| **Storage Location**  | 0001      | Main storage (per plant)                      |

### Finance (R2R)

| Element                 | Value     | Description                                 |
|-------------------------|-----------|---------------------------------------------|
| **Controlling Area**    | 1000      | Single controlling area for all co. codes   |
| **Fiscal Year Variant** | K4        | Calendar year, 12 periods + 4 special       |
| **Posting Period Variant** | 1000   | Standard monthly periods                    |
| **Chart of Accounts**   | CAUS      | US standard chart of accounts (see below)   |
| **Cost Center Hierarchy** | H-1000 | Top node for all cost centers               |
| **Profit Center Hierarchy** | PH-1000 | Top node for all profit centers          |

### Organizational Hierarchy

```
[Client Name] Group
|
|-- CC 1000: Corporate HQ
|   |-- Purchasing Org 1000
|   |-- Plant 1000
|   |-- Cost Centers: 1000xxxx (corporate functions)
|   |-- Profit Centers: PC-CORP-xxx
|
|-- CC 1100: Region East
|   |-- Plant 1100
|   |-- Cost Centers: 1100xxxx (facility operations)
|   |-- Profit Centers: PC-EAST-xxx
|
|-- CC 1200: Region West
|   |-- Plant 1200
|   |-- Cost Centers: 1200xxxx (facility operations)
|   |-- Profit Centers: PC-WEST-xxx
|
|-- CC 1300: Region Central
|   |-- Plant 1300
|   |-- Cost Centers: 1300xxxx (facility operations)
|   |-- Profit Centers: PC-CENT-xxx
```

---

## 4. Chart of Accounts -- Key Account Ranges

| Account Range   | Description                         | Sub-Ledger       |
|-----------------|-------------------------------------|------------------|
| 10000 - 12999   | Fixed Assets                       | Asset Accounting  |
| 11000 - 11499   | Bank Accounts                      | Bank Accounting   |
| 13000 - 13999   | Accounts Receivable                | AR Sub-Ledger     |
| 14000 - 14999   | Intercompany Receivables           | IC Reconciliation |
| 20000 - 20999   | Equity                             | --                |
| 21000 - 21999   | Accounts Payable                   | AP Sub-Ledger     |
| 22000 - 22999   | Accrued Liabilities                | --                |
| 23000 - 23999   | GR/IR Clearing                     | --                |
| 24000 - 24999   | Intercompany Payables              | IC Reconciliation |
| 40000 - 43999   | Revenue                            | --                |
| 44000 - 46999   | Cost of Operations                 | Cost Accounting   |
| 47000 - 47999   | Depreciation Expense               | Asset Accounting  |
| 48000 - 49999   | Administrative Expenses            | Cost Accounting   |
| 50000 - 52999   | Other Income / Expense             | --                |

> **Note:** Replace with actual account ranges from the client's chart of accounts after go-live.

---

## 5. Key Business Roles

| SAP Business Role ID       | Role Name                   | Assigned To (Team)     |
|----------------------------|-----------------------------|------------------------|
| SAP_BR_PURCHASER           | Purchaser                   | P2P consultants        |
| SAP_BR_AP_ACCOUNTANT       | Accounts Payable Accountant | P2P consultants        |
| SAP_BR_GL_ACCOUNTANT       | General Ledger Accountant   | R2R consultants        |
| SAP_BR_MASTER_SPECIALIST_FIN | Finance Master Specialist | R2R team lead          |
| SAP_BR_ADMINISTRATOR       | Administrator               | TKT platform admin     |
| SAP_BR_ANALYTICS_SPECIALIST | Analytics Specialist       | R2R consultants (SAC)  |

---

## 6. Integration Points

| Source System           | Target System              | Integration Method  | Frequency    | Data Flow                          |
|-------------------------|----------------------------|---------------------|--------------|------------------------------------|
| SAP S/4HANA             | SAP Analytics Cloud        | Live Connection     | Real-time    | Financial reporting data           |
| Property Mgmt System    | SAP S/4HANA (AP)           | API / File Upload   | Daily        | Vendor invoices from facility ops  |
| Bank                    | SAP S/4HANA (Bank Stmt)    | BAI2 file import    | Daily        | Bank statement import              |
| Payroll Provider         | SAP S/4HANA (GL)          | File Upload / JE    | Bi-weekly    | Payroll journal entries            |
| SAP S/4HANA (AP)        | Bank                       | Payment file export | Per payment run | Vendor payment files            |
| Azure Monitor            | Log Analytics Workspace   | Diagnostic settings | Continuous   | Session and performance logs       |

---

## 7. SAP Release and Update Schedule

| Item                       | Current Value                             |
|----------------------------|-------------------------------------------|
| **SAP Product**            | SAP S/4HANA Cloud, Public Edition         |
| **Current Release**        | [e.g., 2502]                              |
| **Next Planned Update**    | [e.g., 2505 -- May 2026]                  |
| **Update Frequency**       | Quarterly (SAP-managed)                   |
| **Pre-Update Testing Window** | 4 weeks before go-live in Production   |
| **Downtime Window**        | Saturdays 02:00-06:00 UTC (typical)       |

> After each quarterly update, review all SOPs for navigation and field label changes.

---

## 8. Key Contacts

### Client Side

| Role                        | Name             | Email                      | Phone           |
|-----------------------------|------------------|----------------------------|-----------------|
| IT Director / SAP Owner     | [Name]           | [email]                    | [phone]         |
| Controller                  | [Name]           | [email]                    | [phone]         |
| AP Manager                  | [Name]           | [email]                    | [phone]         |
| Procurement Manager         | [Name]           | [email]                    | [phone]         |
| Facility Operations Lead    | [Name]           | [email]                    | [phone]         |

### TKT Managed Services Team

| Role                        | Name             | Email                      | Focus Area      |
|-----------------------------|------------------|----------------------------|-----------------|
| Engagement Manager          | [Name]           | [email]                    | Overall delivery|
| Senior Consultant (P2P)     | [Name]           | [email]                    | P2P lead        |
| Consultant (P2P)            | [Name]           | [email]                    | P2P support     |
| Senior Consultant (R2R)     | [Name]           | [email]                    | R2R lead        |
| Consultant (R2R)            | [Name]           | [email]                    | R2R support     |

### SAP and Vendor Support

| Role                        | Contact Method                            | When to Use                |
|-----------------------------|-------------------------------------------|----------------------------|
| SAP Support (incidents)     | SAP for Me portal: `https://me.sap.com/` | System issues, bugs        |
| SAP Customer Success Partner | [Name / email]                           | Escalations, update queries|
| Bank IT Contact             | [Name / email / phone]                   | Bank file format issues    |
| Property Mgmt System Vendor | [Name / email / phone]                   | Integration issues         |

---

## 9. Environment-Specific Notes

### Production Rules

- No direct configuration changes in Production. All changes go through the 3-system landscape (DEV > QAS > PRD).
- Transport requests are managed by SAP via the "Manage Software Collection" process.
- Emergency corrections require documented approval from the client IT Director and the TKT Engagement Manager.

### Naming Conventions

| Object Type          | Convention                        | Example                    |
|----------------------|-----------------------------------|----------------------------|
| Cost Centers         | [CC][Region Code][Sequential]     | 1100-0001                  |
| Profit Centers       | PC-[Region]-[Sequential]          | PC-EAST-001                |
| Internal Orders      | IO-[Year]-[Sequential]            | IO-2026-0001               |
| Purchase Orders      | System-assigned (45XXXXXXXX)      | 4500000123                 |
| Journal Entry Ref    | [Mon]-[Year] [Description]        | Feb-2026 Rent Accrual      |

---

## Change Log

| Version | Date       | Author           | Description                     |
|---------|------------|------------------|---------------------------------|
| 1.0     | 2026-02-14 | [Consultant Name] | Initial template created       |
