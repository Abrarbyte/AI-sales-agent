# Data and pipeline audit

**Date:** 27 September 2026
**Scope:** all 15 database tables and every workflow ("pipeline") in the backend
**Method:** read the models and the code that changes stages, then checked the actual records. The records checked are the development database, which is mostly test data, so the counts are small. What matters is what each result shows the system *allows*.

---

## Summary

- **The lead pipeline has the most branches by far.** It has 7 stages and about 22 possible moves, and three separate code paths can mark a lead lost.
- **A lead that has already become a customer can be moved back to "new" or to "closed".** This is how converted leads reappear in the Leads list. It's the most serious finding.
- **The same fact is stored in two places in six areas**, and in four of them the two copies can disagree.
- **Nothing stops the same client being entered twice.** In the test data, one phone number belongs to 6 leads and 4 customers.

---

## 1. Duplicate and overlapping data

### Same fact, stored twice (can disagree)

| # | Fact | Where it's stored | What goes wrong | Seen in the data |
|---|---|---|---|---|
| 1 | **Whether a deal was won or lost** | `Lead.status` (converted / closed) **and** `Negotiation.status` (won / lost) | A negotiation can say "won" while its lead still sits at "proposal". Winning doesn't convert the lead; only the deposit does. | — |
| 2 | **Whether a lead became a customer** | `Lead.status = converted`, `Lead.converted_customer`, `Lead.converted_at` | Three fields for one fact | **1 lead** says "converted" but has no customer |
| 3 | **How far a project has got** | `Customer.project_status` **and** the finished handover milestones | The status is worked out from milestones but stored separately, and can be edited on its own | **1 customer** says "not started" with its go-live milestone finished |
| 4 | **Contact details** | Copied from the lead to the customer at conversion | Updating a customer's phone number leaves the old one on the lead | no drift yet |
| 5 | **Who is an admin** | `User.role` **and** Django's `is_superuser` | Fixed in PR #3: the first admin account was refused by the console | fixed |
| 6 | **Whether the client was interested in a demo** | `Demo.outcome` **and** `Demo.interested` | Two answers to one question | 1 demo is "successful" with `interested` left blank |

### Fields that overlap in meaning

| Fields | Overlap |
|---|---|
| `Negotiation.terms` / `payment_terms` / `payment_terms_note` | Three places to write the payment terms |
| `Lead.requirement` / `Negotiation.requirements` / `Negotiation.scope` / `Negotiation.proposed_solution` | Four places describing what the client wants |
| `Lead.budget` / `Negotiation.quoted_amount` / `Lead.value` | Three different amounts. This one is **intentional** (their budget, our quote, the agreed price) but isn't labelled clearly |
| `Attendance`, `Checkpoint` and `FieldVisit` all record a GPS location | Three location logs. Merging them was tried on 22 Sep and **rolled back on purpose** |

### Money with nowhere to go

| Problem | Seen in the data |
|---|---|
| The agreed price (`value`) and money received (`amount_paid`) live **only on the lead**. The customer record has neither. | 6 customers have their value only on their old lead |
| A customer created directly, not converted from a lead, has **no price and no payments at all** | **2 of 8** customers |
| The deposit rule is fixed at **30%**, whatever payment terms were agreed (full advance, half-and-half, milestones) | — |

→ Payments (PR B) must give the **customer** its own agreed value and payment list, not keep reading the lead's.

### Leftovers from the earlier retail design

Words from the original goods-delivery version are still in the handover workflow: `out_for_delivery`, `not_delivered`, `received_by`, "delivery attempts", and on visits, the outcome `order_placed`. They work, but they don't describe a website or app project.

### Duplicate records

| Check | Result |
|---|---|
| Leads sharing one phone number | **6** leads share `9812345678` |
| Customers sharing one phone number | **4** customers share the same number |
| A customer who is also an **open lead** | **4** |
| Protection against duplicates | **None.** No check when adding a lead or customer. |

In the test data this is one placeholder number reused. In real use, it means two reps can enter the same client and the system won't notice.

---

## 2. Pipelines, ranked by branches

A "branch" is a point where a record can go more than one way.

| Rank | Pipeline | Stages | Possible moves | Branch points |
|---|---|---|---|---|
| **1** | **Lead** | 7 | ~22 | every open stage can go forward, to Won, or to Lost |
| 2 | Handover (delivery) | 5 | ~8 | done / failed and retry / cancelled, **with a retry loop** |
| 3 | Negotiation | 5 | ~7 | proposal sent, on hold (and back), won, lost |
| 4 | Visit outcome | 5 | 5 | ends the visit; "follow up" creates a follow-up |
| 5 | Demo outcome | 4 | 4 | "rescheduled" loops back |
| 6 | Customer project | 5 | 4 | a straight line, moved by handover milestones |
| 7 | Follow-up | 3 | 2 | done or cancelled; "overdue" is worked out from the time |
| 8 | Support | 3 | 3 | none → open → resolved → open again |
| 9 | Attendance | 2 | 1 | check in → check out |

### The lead pipeline in detail

```
new ──► assigned ──► demo ──► negotiation ──► proposal
 │         │          │           │              │
 └─────────┴──────────┴───────────┴──────────────┴──► converted (Won)  needs a 30% deposit
 └─────────┴──────────┴───────────┴──────────────┴──► closed    (Lost)
```

**Three different ways a lead becomes "closed":**

| Path | Records a reason? |
|---|---|
| Someone marks it closed | **Not required** |
| Its negotiation is marked lost | **No** |
| Nobody touched it for 30 days (automatic) | **No**, even though a "no response" reason exists |

In the data, **1 of 2** closed leads has no reason.

### Moves the system allows but shouldn't

We tested these against the API, and every change was rolled back afterwards:

| Move | Allowed? | Problem |
|---|---|---|
| proposal → new | **Yes** | a lead can jump backwards with no record of why |
| negotiation → assigned | **Yes** | same |
| **converted → closed** (already a customer) | **Yes** | a paying customer's lead counts as lost |
| **converted → new** (already a customer) | **Yes** | **the converted lead reappears in the Leads list** |
| closed → new (reopen) | Yes | probably fine, but it isn't recorded as a reopen |
| new → closed with no reason | Yes | see above |

---

## 3. Recommended fixes

| Priority | Fix | Goes in |
|---|---|---|
| **High** | Once converted, a lead's stage is locked | PR A |
| **High** | "Closed" becomes **"Lost"** and always needs a reason. The automatic close records "no response for 30 days". Existing blank reasons get filled in. | PR A |
| **High** | The Leads list shows open leads only, with a switch to show won and lost | PR A |
| **High** | The customer gets its own agreed value and payment list; the deposit becomes the first payment | PR B |
| Medium | Warn when a new lead or customer has a phone number that's already in the system | later |
| Medium | Negotiation "won / lost" stops being a separate answer. It follows the lead, or is removed. | later |
| Medium | Project status is always worked out from the milestones, never edited separately | PR C |
| Medium | Backward moves need a reason, or are blocked | later |
| Low | Merge the overlapping text fields (terms, requirements) | later |
| Low | Replace the retail words in handovers | later |
| Low | Remove `Demo.interested`, since `outcome` already answers it | later |

---

## 4. Test run with 20 realistic leads — 27 Sep

Twenty leads were created **through the real API**, the same way the phone and
console create them. They covered every stage and feature: 14 demos, 11
negotiations, 7 proposal PDFs, 4 conversions with deposits, 20 handover
milestones (8 delivered with proof photos, 1 failed attempt), 13 visits and 6
site check-ins with photos, 16 follow-ups, attendance, and 2 lost leads. The API
refused none of it. Then each risky move was tried on top of that data, and every
change was rolled back (record counts were identical before and after).

### What works
- Photos from visits, check-ins and handover proofs are all stored as WebP.
- Handover milestones move the project forward and never back.
- Converting refuses a deposit below 30%.
- ~~A demo can't be logged on a lost lead.~~ **Corrected 29 Sep:** it can. The check that
  seemed to prove this was refused only because its request was missing a required
  field. The permanent tests caught it; now GitHub issue #54.
- Assigning a lead to someone else notifies them.
- Visits, check-ins and attendance reach the console completely.

### Confirmed bugs

| # | Bug | Found by |
|---|---|---|
| 1 | **Records with no owner and no creator can't be seen by anyone, not even the super admin.** 7 leads and 6 customers were missing from the console and the Excel export. The Django admin site doesn't fill in the creator, so leads added there without an owner disappear. | comparing the console's data with the database |
| 2 | A lead that's already a customer can be moved back to "new" or "lost" | stage test |
| 3 | Leads can move backwards with no record of why | stage test |
| 4 | **A lead with no price converts with ₹0 paid.** The deposit rule is skipped. | probe |
| 5 | Paid can be more than the price (₹90,000 on a ₹50,000 deal) | probe |
| 6 | A negative price is accepted | probe |
| 7 | **Converting creates a second customer** when the client already is one | probe |
| 8 | **Losing a lead leaves its follow-ups pending.** The rep keeps getting reminders about a dead lead. | probe |
| 9 | **The 30-day auto-close closed a lead with a meeting booked for the next day**, with no reason recorded | probe |
| 10 | Marking a negotiation **Won** doesn't move the lead. All 4 converted test leads still show their negotiation as "proposal sent". | probe + test data |
| 11 | A lead can be assigned to a deactivated rep | probe |
| 12 | **Deactivating a rep leaves their open leads with nobody** who can work them | probe |
| 13 | **The "Assigned" stage is never set.** Leads stay "New" even after an admin hands them to a rep. | test data + probe |
| 14 | Delivering a handover **overwrites the notes** written when it was scheduled | test data + probe |
| 15 | A lead can be marked lost with no reason, in three different ways | probe |
| 16 | **The "Design" project stage is never reached.** Design approval jumps straight from "not started" to "development". | test data |

### The console doesn't show
- **Money received and deposit status** on leads
- **Which customer a lead became**
- **The products a customer bought**
- Reference links, and who created each record

### Other notes
- **Leads can be permanently deleted through the API**, although the project's rule is "deactivate, never delete".
- When a lead converts, its booked follow-ups stay on the lead instead of moving to the new customer.
- The product catalogue still has **"Solar 5kW"**, left over from the retail version.

---

## 5. Round 2: 20 journeys, as the console shows them — 27 Sep

Twenty more leads, each on its own journey: different requirements, deal sizes
(₹10,000 to ₹12,00,000), payment terms, discounts (0–15%), timelines (2–16
weeks), demo histories (rescheduled, partial then successful, unsuccessful), a
reassignment, a loss followed by a reopen and a win, failed handover attempts,
an auto-closed quiet lead, and an overdue follow-up. The API gave 0 errors. One
refusal was expected: a 10% deposit was correctly stopped from converting.

**20 of 20 ended at the right stage.** Stage moves work. But in the console's
Leads screen, **6 of the 20 look wrong or incomplete to a manager**:

| Lead | The console shows | What's actually true |
|---|---|---|
| Lotus Pharmacy, Deccan Motors, Patel Hardware | Negotiation / Proposal with **no value** | Quotes of ₹1.6L, ₹1.75L and ₹2.1L exist. **The negotiation's quote never fills the lead's price**, so these deals are missing from every total. |
| Vertex Logistics | an ordinary "Negotiation", ₹7.5L | The rep marked the negotiation **won**, and it's waiting on ₹1.5L of deposit. **The console shows neither.** |
| Om Gym | Converted, ₹40K | **₹70K was recorded as paid**, on a ₹40K deal. The console never shows money paid, so nobody would notice. |
| Sharma Tuition | Converted, **no value** | It became a customer with no price and nothing paid |
| Orbit Coworking, Quiet Traders | Closed | **No reason recorded.** One was lost through its negotiation, the other auto-closed. The Leads list doesn't show lost reasons at all. |

Also confirmed on the screen:
- **Converted leads fill the Leads list:** 11 of these 20 rows are already customers.
- Overdue follow-ups are correctly shown in red (Lotus Pharmacy).
- The reassigned lead correctly shows its new owner (Konkan Resorts).
