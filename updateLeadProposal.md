# Update lead proposal API

**Version:** 1.0  
**Function:** `updateLeadProposal`  
**Method:** `POST`  
**Purpose:** Let a partner mark their own lead `proposal_accepted` or `closed_lost`.

**Related:** Same partner API keys as [Partner Lead Submit](./Partner-Lead-Submit-API.md). Current status is readable with [Get Leads](./partnerGetLeads.md). Status and job changes are also pushed to the partner `webhookUrl`. Set that URL with [POST /partnerWebhookSubscriptions](./partnerWebhookSubscriptions.md).

---

## 1. When to use this endpoint

| Scenario | What happens |
| -------- | ------------ |
| Customer accepts the proposal | `outcome=proposal_accepted`. The lead becomes `proposal_accepted` / `won`. The response does not include a job. |
| Customer does not proceed | `outcome=closed_lost`. The lead is closed. No install job is created. |
| Same request is sent again | Success, with no second job. |
| The other outcome was already saved | `409`. |

A heat-trial accept does not create the install job. Installio creates that job later, at Sales Handover. The partner then receives `job.created` with `lead_id`, `job_id`, and `job_ref`.

A solar accept also updates the lead only. The install job waits until Design Validated.

A lead that is not waiting on Sales Handover or Design Validated still creates the install job in this request. The response still has no job fields. `job.created` carries the job.

The request is on the lead. There is no proposal id.

---

## 2. Endpoint

**Development (example):**

`https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/updateLeadProposal`

**Production (example):**

`https://europe-west2-co-pilot-b7f8e.cloudfunctions.net/updateLeadProposal`

Auth matches the other partner endpoints: `Authorization: Bearer <partner-api-key>`.

---

## 3. Request

```json
{
  "leadId": "abc123",
  "outcome": "proposal_accepted"
}
```

`lead_id` is accepted as an alias of `leadId`. `outcome` is `proposal_accepted` or `closed_lost`. The lead must belong to the authenticated partner.

---

## 4. Success

```json
{
  "success": true,
  "lead_id": "abc123",
  "outcome": "proposal_accepted",
  "sales_status": "proposal_accepted",
  "sales_phase": "won"
}
```

`closed_lost` returns `sales_phase: "lost"`. The response has no `install_job` field.

A repeat includes `"idempotent": true`.

The job is not in this response. When Installio creates it, `job.created` is sent to the partner webhook. Sales Handover is internal: partners keep seeing `proposal_accepted`, not `ready_for_oms`.

---

## 5. Errors

| HTTP | Meaning |
| ---- | ------- |
| 400 | Missing `leadId`, or `outcome` is not `proposal_accepted` or `closed_lost` |
| 401 | Missing or invalid API key |
| 403 | Partner disabled, or the lead belongs to another partner |
| 404 | Unknown lead or partner |
| 409 | Lead is already `proposal_accepted` or `closed_lost` with the other outcome |
| 500 | This request was supposed to create the install job and it failed. The lead may already show `proposal_accepted`. Retry the same request. Heat-trial and solar accepts do not create the job here, so they do not return this error. |
| 502 | The lead could not be moved to that outcome. The lead was not changed. |
