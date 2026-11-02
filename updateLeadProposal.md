# Update Lead Proposal API

**Version:** 1.0  
**Function:** `updateLeadProposal`  
**Method:** `POST`  
**Purpose:** Mark an existing partner lead `proposal_accepted` or `closed_lost`. Acceptance on a heat lead creates one installation job. `closed_lost` closes the lead and creates no job.

**Related:** Uses the **same partner API keys** as [Partner Lead Submit](./Partner-Lead-Submit-API.md). The `leadId` must belong to the authenticated partner. Read the current status with [Get Leads](./partnerGetLeads.md). Status and job changes are also pushed to the partner `webhookUrl` ([Partner API overview](./Partner%20API%20Overview.md)).

**Also see:** [Partner API overview](./Partner%20API%20Overview.md) (environments, auth, rate limits, errors).

---

## 1. When to use this endpoint

| Scenario | What happens |
| -------- | ------------ |
| The customer accepts the proposal | `outcome` is `proposal_accepted`. A **heat** lead creates one installation job. |
| The customer does not proceed | `outcome` is `closed_lost`. The lead is closed. No installation job is created. |
| The same outcome is sent again | **200**. No second job is created. The body includes `"idempotent": true`. |
| The other outcome was already saved | **409**. The lead is not changed. |

A **solar** `proposal_accepted` updates the lead only. The installation job still waits until design validation, which is the existing hand-off.

The request updates the lead as a whole. There is no proposal id. One lead has one design. If several designs exist upstream, mark the sold design there before calling this endpoint.

This endpoint does **not** change customer contact, callback preferences, or `outreachAllowed`. Use [Update Lead Customer](./updateLeadCustomer.md) for those.

---

## 2. Endpoint and method

- **Method:** `POST` only (`PATCH` / `GET` return **405**)
- **Content-Type:** `application/json`

**Development (example):**

```
https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/updateLeadProposal
```

**Production (example):**

```
https://europe-west2-co-pilot-b7f8e.cloudfunctions.net/updateLeadProposal
```

**Local emulator (example):**

```
http://127.0.0.1:5001/co-pilot-dev-f762b/europe-west2/updateLeadProposal
```

Confirm the exact URL with your platform administrator before go-live.

---

## 3. Authentication

Every request must include a valid **partner API key** (same issuance process as Partner Lead Submit).

**Recommended header:**

```http
Authorization: Bearer <partner-api-key>
```

**Alternative formats** (also accepted):

```http
Authorization: ApiKey <partner-api-key>
Authorization: api-key <partner-api-key>
Authorization: <partner-api-key>
```

| Result | HTTP |
| ------ | ---- |
| Missing / invalid key | **401** |
| Disabled key | **401** |
| Optional `partnerId` in body does not match the key’s partner | **403** |
| Partner disabled in config | **403** |
| Lead belongs to another partner | **403** |

The lead must belong to the partner on the API key.

---

## 4. Request body

Fields may be at the **root** of the JSON body or inside a wrapped `data` object.

| Field | Type | Required | Description |
| ----- | ---- | -------- | ----------- |
| `leadId` | string | yes | Lead ID from a prior create response, or from [Get Leads](./partnerGetLeads.md). `lead_id` is accepted as an alias. |
| `outcome` | string | yes | `proposal_accepted` or `closed_lost`. Any other value returns **400**. |

```json
{
  "leadId": "abc123",
  "outcome": "proposal_accepted"
}
```

---

## 5. Success

**HTTP 200**

Heat acceptance:

```json
{
  "success": true,
  "lead_id": "abc123",
  "outcome": "proposal_accepted",
  "sales_status": "proposal_accepted",
  "sales_phase": "won",
  "install_job": {
    "created": true,
    "job_id": "firestore-project-id",
    "job_ref": "IN-1001",
    "already_existed": false
  }
}
```

`closed_lost` returns `sales_status` `closed_lost`, `sales_phase` `lost`, and `install_job` `null`.

A solar acceptance returns:

```json
"install_job": {
  "created": false,
  "reason": "solar_waits_for_design_validated"
}
```

A repeat of the same outcome includes `"idempotent": true`. `already_existed` is `true` when the installation job was already there.

`sales_phase` for `proposal_accepted` is `won`. `sales_phase` for `closed_lost` is `lost`. Later status changes still arrive on `sales.status_changed`. A new installation job can also arrive on `job.status_changed`.

Sending the same `proposal_accepted` request again is safe. It does not create a second installation job.

---

## 6. Errors

| HTTP | Meaning |
| ---- | ------- |
| **400** | Body is not a JSON object, `leadId` is missing, or `outcome` is not `proposal_accepted` or `closed_lost` |
| **401** | Missing, invalid, or disabled API key |
| **403** | Partner disabled, partner mismatch, or the lead belongs to another partner |
| **404** | Unknown lead, or the partner was not found |
| **405** | Method is not `POST` |
| **409** | The lead is already closed with the other outcome |
| **429** | Partner rate limit exceeded |
| **500** | The installation job was not created. The lead may already show `proposal_accepted`. Retry the same request. |
| **502** | The deal stage could not be moved. The lead was not changed. |

Error body:

```json
{
  "success": false,
  "error": "outcome must be proposal_accepted or closed_lost"
}
```

A **409** also includes `lead_id` and the current `sales_status`. A **500** from a failed job create includes `lead_id`, `sales_status` `proposal_accepted`, and `"retryable": true`.
