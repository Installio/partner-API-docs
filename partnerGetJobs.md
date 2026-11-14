# Get Jobs API

**Version:** 1.0  
**Function:** `jobs`  
**Method:** `GET`  
**Purpose:** Discover and reconcile partner-scoped jobs. Use it to find a survey or remedial Installio raised, and to catch up when a job webhook was missed.

**Related:** Same partner API keys as [Get Leads](./partnerGetLeads.md). Job changes are also pushed on the partner `webhookUrl` ([Partner API overview](./Partner%20API%20Overview.md)).

---

## 1. When to use this endpoint

| Scenario | Endpoint |
| -------- | -------- |
| List or look up jobs for CRM reconciliation | `jobs` (GET) |
| List or look up leads | `leads` (GET) |
| Receive a push when a job's status changes | partner `webhookUrl` (`job.status_changed`) |
| Receive a push when a job is scheduled, rescheduled, or unscheduled | partner `webhookUrl` |

`lead_id` returns jobs linked to that lead. It does not include other jobs on the same property that are not linked to the lead.

---

## 2. Endpoint and method

- **Method:** `GET` only (`POST` / `PATCH` → **405**)
- **Auth:** Partner API key in `Authorization` (same formats as other Partner API endpoints)

**Development (example):**

```
https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/jobs
```

**Production (example):**

```
https://europe-west2-co-pilot-b7f8e.cloudfunctions.net/jobs
```

---

## 3. Query parameters

| Param | Aliases | Type | Description |
| ----- | ------- | ---- | ----------- |
| `job_id` | `jobId` | string | Fetch a single job by id (still partner-scoped) |
| `lead_id` | `leadId` | string | Jobs linked to this lead |
| `property_id` | `propertyId` | string | Jobs that store this property id |
| `job_type` | `jobType` | string | `survey`, `install`, `firstFix`, `remedial`, `service`, `callOut`, or `other` |
| `status` | — | string | Filter by job status |
| `updated_after` | `updatedAfter` | ISO-8601 | Keep jobs with `updated_at` ≥ this timestamp |
| `limit` | — | integer | Page size (default `50`, max `100`) |
| `cursor` | — | string | Opaque pagination cursor from a previous `next_cursor` |

Notes:

- List queries are scoped to the partner on the API key. Jobs belonging to other partners are never returned (**403** on a single-job or cursor mismatch).
- `lead_id`, `property_id`, `job_type`, `status`, and `updated_after` are applied after the partner-scoped Firestore page. Continue with `next_cursor` if a filtered page is short.
- `property_id` matches the id stored on the job. Many jobs do not have one yet, so a property filter can be empty.
- A `lead_id` that belongs to another partner returns **403**. A missing lead returns **404**.
- Sorting is newest-first by the job's created date.

---

## 4. Success response

```json
{
  "success": true,
  "partner_id": "acme-ltd",
  "jobs": [
    {
      "job_id": "project-id",
      "job_ref": "INS-100",
      "job_type": "survey",
      "status": "inPlanning",
      "lead_id": "lead-id",
      "project_id": "project-id",
      "property_id": null,
      "timezone": "Europe/London",
      "schedule": {
        "start_at": "2026-06-14T08:00:00.000Z",
        "end_at": null,
        "start_time": "2026-06-14T08:00:00.000Z"
      },
      "created_at": "2026-06-01T09:00:00.000Z",
      "updated_at": "2026-06-02T09:00:00.000Z"
    }
  ],
  "next_cursor": "eyJpZCI6InByb2plY3QtaWQifQ"
}
```

When `job_id` is provided, the same shape is returned with a single entry in `jobs`, a top-level `job` object, and `next_cursor: null`.

`timezone` is always `Europe/London`. Schedule instants are ISO-8601 UTC. A schedule field is `null` when that date or time is not set. `property_id` is `null` when the job has no property id.

This response does not include tasks, documents, or serial numbers.

---

## 5. Errors

| HTTP | Meaning |
| ---- | ------- |
| `400` | Invalid `limit`, `cursor`, `updated_after`, or unknown `job_type` |
| `401` | Missing/invalid/disabled API key |
| `403` | Partner disabled, or job, lead, or cursor not owned by this partner |
| `404` | Partner, job, or lead not found |
| `405` | Method not allowed |
| `429` | Rate limit exceeded |
| `500` | Internal error (including missing Firestore composite index) |

The list query orders by `created_date` for one partner. That needs a Firestore composite index on `projects`: `partner_id` ascending, `created_date` descending.

---

## 6. Examples

**Jobs for a lead**

```http
GET /jobs?lead_id=abc123
Authorization: Bearer <partner-api-key>
```

**Single job**

```http
GET /jobs?job_id=project-id
Authorization: Bearer <partner-api-key>
```

**Surveys only**

```http
GET /jobs?job_type=survey&limit=25
Authorization: Bearer <partner-api-key>
```
