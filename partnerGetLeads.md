# Get Leads API

**Version:** 1.1  
**Function:** `leads`  
**Method:** `GET`  
**Purpose:** Discover and reconcile partner-scoped leads, including Installio-normalized commercial sales status (`sales_status` / `sales_phase`).

**Related:** Same partner API keys as [Partner Lead Submit](./Partner-Lead-Submit-API.md). Sales status changes are also pushed via the `sales.status_changed` webhook ([Partner API overview](./Partner%20API%20Overview.md)).

---

## 1. When to use this endpoint

| Scenario | Endpoint |
| -------- | -------- |
| Create a new lead | `partnerLeadSubmit` / `partnerEstimateSubmit` |
| Correct customer contact / callback | `updateLeadCustomer` |
| **List or look up leads for CRM reconciliation** | **`leads` (GET)** |
| Receive push updates on sales status | partner `webhookUrl` (`sales.status_changed`) |

Use **GET `/leads`** to pull the current Installio sales status for leads that belong to your partner.

---

## 2. Endpoint and method

- **Method:** `GET` only (`POST` / `PATCH` → **405**)
- **Auth:** Partner API key in `Authorization` (same formats as other Partner API endpoints)

**Development (example):**

```
https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/leads
```

**Production (example):**

```
https://europe-west2-co-pilot-b7f8e.cloudfunctions.net/leads
```

---

## 3. Query parameters

| Param | Aliases | Type | Description |
| ----- | ------- | ---- | ----------- |
| `lead_id` | `leadId` | string | Fetch a single lead by id (still partner-scoped) |
| `limit` | — | integer | Page size (default `50`, max `100`) |
| `cursor` | — | string | Opaque pagination cursor from a previous `next_cursor` |
| `sales_status` | `salesStatus` | string | Filter by Installio fine-grain status (snake_case) |
| `lead_type` | `leadType` | string | Filter by `heat` or `solar` |
| `updated_after` | `updatedAfter` | ISO-8601 | Keep leads with `updated_at` ≥ this timestamp |

Notes:

- List queries are scoped to `partnerId` from the API key. Leads belonging to other partners are never returned (**403** on single-lead mismatch).
- `sales_status` / `lead_type` / `updated_after` are applied after the partner-scoped Firestore page (continue with `next_cursor` if a filtered page is short).
- Sorting is newest-first by `created_at`.

---

## 4. Success response

```json
{
  "success": true,
  "partner_id": "acme-ltd",
  "leads": [
    {
      "lead_id": "abc123",
      "partner_id": "acme-ltd",
      "lead_type": "heat",
      "status": "new",
      "sales_status": "survey_booked",
      "sales_phase": "survey",
      "submission_channel": "partner_lead_api",
      "customer": {
        "first_name": "Jane",
        "last_name": "Smith",
        "email": "jane.smith@example.com",
        "phone": "07123456789"
      },
      "property": {
        "address": "123 High Street, London",
        "postcode": "SW1A 1AA"
      },
      "ecs": {
        "external_id": "ecs-job-001",
        "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
        "installio_job_ref": "installio-ref-123",
        "metadata": { "sourceSystem": "ecs-middleware" }
      },
      "created_at": "2026-07-01T10:00:00.000Z",
      "updated_at": "2026-07-15T12:30:00.000Z"
    }
  ],
  "next_cursor": "eyJpZCI6ImFiYzEyMyJ9",
  "warnings": []
}
```

When `lead_id` is provided, the same shape is returned with a single entry in `leads` and a top-level `lead` object for convenience. `next_cursor` is `null`.

### Field notes

| Field | Description |
| ----- | ----------- |
| `sales_status` | Installio snake_case status. Unmapped values are returned as `null`. |
| `sales_phase` | Coarse phase: `new`, `qualifying`, `survey`, `quote`, `validation`, `won`, `lost` |
| `ecs` | Present when ECS metadata was stored on the lead; otherwise `null` |

Supported `sales_status` values: `new`, `attempted_contact`, `contacted`, `consultation_booked`, `consultation_completed`, `survey_required`, `survey_booked`, `survey_in_progress`, `survey_completed`, `quote_in_progress`, `proposal_sent`, `proposal_accepted`, `validation_survey_booked`, `validation_survey_completed`, `validation_in_progress`, `validation_completed`, `won`, `closed_lost`.

---

## 5. Errors

| HTTP | Meaning |
| ---- | ------- |
| `400` | Invalid `limit`, `cursor`, `updated_after`, or unknown `sales_status` filter |
| `401` | Missing/invalid/disabled API key |
| `403` | Partner disabled, or lead/cursor not owned by this partner |
| `404` | Partner or lead not found |
| `405` | Method not allowed |
| `429` | Rate limit exceeded |
| `500` | Internal error (including missing Firestore composite index) |

---

## 6. Examples

**List recent leads**

```http
GET /leads?limit=25
Authorization: Bearer <partner-api-key>
```

**Single lead**

```http
GET /leads?lead_id=abc123
Authorization: Bearer <partner-api-key>
```

**Reconcile by sales status**

```http
GET /leads?sales_status=proposal_sent&limit=50
Authorization: Bearer <partner-api-key>
```
