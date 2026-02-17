# TKT Azure Platform v8 -- Knowledge Base

## Purpose

This knowledge base supports the TKT managed services team (4 SAP consultants) providing Procure-to-Pay (P2P) and Record-to-Report (R2R) services for a self-storage company running SAP S/4HANA Public Cloud.

The strategic objective is to build a structured, searchable body of knowledge so that:

- Junior consultants can resolve common issues independently.
- AI analysis of weekly session logs can identify SOP gaps and recommend new articles.
- Knowledge is retained when team members rotate or leave.
- Month-end and quarter-end processes are repeatable and auditable.

---

## Directory Structure

```
knowledge-base/
|-- README.md                        # This file
|-- P2P/                             # Procure-to-Pay domain
|   |-- how-to/                      # Step-by-step SOPs (SOP-P2P-NNN-*.md)
|   |-- troubleshooting/             # Error resolution guides (TS-P2P-NNN-*.md)
|   |-- configuration/               # Config documentation (CFG-P2P-NNN-*.md)
|-- R2R/                             # Record-to-Report domain
|   |-- how-to/                      # Step-by-step SOPs (SOP-R2R-NNN-*.md)
|   |-- troubleshooting/             # Error resolution guides (TS-R2R-NNN-*.md)
|   |-- configuration/               # Config documentation (CFG-R2R-NNN-*.md)
|-- cross-functional/                # Processes spanning both domains
|-- client-specific/                 # Client landscape, org structure, contacts
|-- weekly-reports/                  # AI-generated weekly analysis reports
```

---

## How to Add a New Article

### 1. Determine the Category

| Category          | Use When                                                        | Prefix   |
|-------------------|-----------------------------------------------------------------|----------|
| how-to            | Documenting a repeatable process with clear steps               | SOP-     |
| troubleshooting   | Resolving a specific error, warning, or unexpected behavior     | TS-      |
| configuration     | Recording system settings, business rules, or custom config     | CFG-     |
| cross-functional  | Process spans both P2P and R2R (e.g., month-end close)          | XF-      |
| client-specific   | Client environment details, contacts, org structure             | CS-      |

### 2. Assign a Document ID

Use the next available sequential number within the domain and category:

```
SOP-P2P-001   (first P2P how-to)
SOP-P2P-002   (second P2P how-to)
TS-R2R-001    (first R2R troubleshooting)
CFG-P2P-001   (first P2P configuration)
```

### 3. Use the Correct Template

All SOPs must follow the template established in `SOP-P2P-001-create-purchase-order.md`. The required sections are:

```markdown
# SOP-[DOMAIN]-[NNN]: [Title]

## Metadata
- **Document ID:** SOP-[DOMAIN]-[NNN]
- **Domain:** P2P | R2R
- **Category:** How-To | Troubleshooting | Configuration
- **Fiori App:** [App Name] ([App ID])
- **SAP Role Required:** [Business Role ID]
- **Created:** YYYY-MM-DD
- **Last Updated:** YYYY-MM-DD
- **Author:** [Name]
- **Reviewed By:** [Name]
- **Version:** [N.N]

## Purpose
[One to two sentences describing when and why to use this SOP.]

## Prerequisites
[Bulleted list of what must be true before starting.]

## Step-by-Step Procedure
[Numbered steps with Fiori navigation paths.]

## Validation and Verification
[How to confirm the process completed successfully.]

## Common Errors and Resolutions
[Table of error messages, root causes, and fixes.]

## Related SOPs
[Links to related documents.]

## Change Log
[Table tracking revisions.]
```

### 4. File Naming Convention

```
SOP-P2P-001-create-purchase-order.md
TS-R2R-003-fx-revaluation-error.md
CFG-P2P-002-approval-workflow-config.md
```

Rules:
- All lowercase after the prefix.
- Use hyphens to separate words.
- Keep the description concise (3-5 words).

### 5. Submit for Review

- Create a pull request with the new article.
- Tag at least one other team member as a reviewer.
- Ensure the article has been tested against the DEV or QAS system before merging.

---

## How Weekly Log Reports Feed Into Knowledge Building

### The Feedback Loop

```
Session Logs (Azure Monitor)
        |
        v
Weekly KQL Export (templates/weekly-log-export-query.json)
        |
        v
AI Analysis (weekly-reports/REPORT-TEMPLATE.md)
        |
        v
Identified Gaps and Recommendations
        |
        v
New or Updated Knowledge Base Articles
```

### Process

1. **Data Collection (Automated):** Azure Monitor and Log Analytics capture session data from the team's AVD desktops -- Fiori apps launched, pages visited, Teams calls, errors encountered, and time-on-task.

2. **Weekly Export (Scheduled):** A scheduled query using the KQL templates in `templates/weekly-log-export-query.json` runs every Monday at 06:00 UTC and exports the previous week's data.

3. **AI Analysis (Semi-Automated):** The exported data is fed into the AI analysis pipeline, which produces a structured report following `weekly-reports/REPORT-TEMPLATE.md`. The AI identifies:
   - Repetitive tasks that lack an SOP.
   - Errors that recur across multiple consultants.
   - Processes where time-on-task is significantly above baseline.
   - Fiori apps being used that have no corresponding documentation.

4. **Human Review (Weekly):** During the Monday team stand-up, the team reviews the AI report and decides:
   - Which SOP gaps to address (assigned as backlog items).
   - Which troubleshooting guides to create based on recurring errors.
   - Whether existing SOPs need updates based on observed behavior.

5. **Article Creation:** New articles are drafted using the templates above, reviewed, and merged into the knowledge base.

### Metrics Tracked

| Metric                        | Target                  | Source                   |
|-------------------------------|-------------------------|--------------------------|
| SOP coverage (% of Fiori apps)| > 90%                  | Knowledge base vs. usage |
| Recurring errors documented   | 100% of top-10 errors   | Weekly AI report         |
| Average resolution time       | Decreasing trend        | Session logs             |
| Junior consultant self-serve  | > 70% of issues         | Support ticket analysis  |

---

## Maintenance

- **Quarterly Review:** All SOPs are reviewed for accuracy against the current S/4HANA Public Cloud release.
- **After Each SAP Update:** SAP pushes quarterly feature updates to Public Cloud tenants. After each update, verify that Fiori navigation paths and field labels in SOPs still match the live system.
- **Retirement:** Outdated SOPs are moved to an `archive/` subdirectory with a note explaining why they were retired.

---

## Contact

For questions about the knowledge base structure or contribution process, contact the TKT platform team lead.
