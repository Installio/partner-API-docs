# Partner API Overview

**Audience:** External partner engineering teams integrating CRM and lead flows  
**Status:** Shareable externally  
**Version:** 1.1

This document is the standalone overview for the Installio/Breengy Partner API. It covers environments, authentication, endpoint selection, usage guidance, rate limiting, webhook events, and error handling.

---

## 1. Base URLs and environments

All endpoints are deployed as Google Cloud Functions in `europe-west2`.

- **Development (example):**  
  `https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net`
- **Production (example):**  
  `https://europe-west2-co-pilot-b7f8e.cloudfunctions.net`
- **Local emulator (example):**  
  `http://127.0.0.1:5001/<project-id>/europe-west2`

Confirm exact URLs with your platform administrator before go-live.

---

## 2. Authentication

Every Partner API endpoint uses a partner API key in the `Authorization` header.

Recommended format:

```http
Authorization: Bearer <partner-api-key>
```

Also accepted:

```http
Authorization: ApiKey <partner-api-key>
Authorization: api-key <partner-api-key>
Authorization: <partner-api-key>
```

Behavior:

- Missing/invalid key -> `401`
- Disabled key -> `401`
- Valid key attributes each request to one `partnerId`

---

## 3. Endpoint catalog

| Endpoint                 | Method(s)       | Purpose                                                                                                              | Details                                                        |
| ------------------------ | --------------- | -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `/partnerLeadSubmit`     | `POST`          | Full lead flow: heat (`leadType=heat`) or solar (`leadType=solar`); `leadType` required                              | [Partner-Lead-Submit-API.md](./Partner-Lead-Submit-API.md)     |
| `/updateLeadCustomer`    | `PATCH`         | Update customer contact and/or `callbackRequest` on an existing lead                                                 | [updateLeadCustomer.md](./updateLeadCustomer.md)               |
| `/leads`                 | `GET`           | List/fetch partner-scoped leads with Installio `sales_status` / `sales_phase`                                        | [partnerGetLeads.md](./partnerGetLeads.md)                     |
| `/partnerEstimateSubmit` | `POST`          | Heat pump estimate only (no Spruce job)                                                                              | [partnerEstimateSubmit.md](./partnerEstimateSubmit.md)         |
| Job status webhook       | Partner webhook | OMS → Partner                                                                                                        | Sends `job.status_changed` updates to partner `webhookUrl`     |
| Sales status webhook     | Partner webhook | OMS → Partner                                                                                                        | Sends `sales.status_changed` updates to partner `webhookUrl`   |

---

## 4. Usage guide

## 4.1 Job status webhook flow

When an Installio job/project status changes, OMS may send a webhook to your configured `webhookUrl`.

Trigger behavior:

- Sends webhook only when the job status value actually changes.
- Delivery is partner-scoped (only for jobs belonging to your partner).
- `job_id` is included when available.

Delivery to partner `webhookUrl`:

- Method: `POST`
- Header: `Content-Type: application/json`
- User agent: `Installio-Partner-Webhook/1.0`
- Timeout: 8 seconds
- Success criteria: any `2xx` response from partner endpoint
- Non-`2xx` or timeout/network errors are logged as delivery failures

## 4.1.1 Sales status webhook flow

When a lead’s Installio `sales_status` changes, OMS may send a webhook to the same partner `webhookUrl`.

Trigger behavior:

- Reads fine-grain `sales_status` and coarse `sales_phase` (Installio snake_case).
- Sends webhook only when `old_sales_status !== new_sales_status`.
- Delivery is partner-scoped via the same webhook subscription(s) as job status events.
- Uses the same delivery rules (HTTPS POST, 8s timeout, `2xx` success, best-effort logging on failure).
- If status advances several steps in one update, you receive a single event with the previous and new values (intermediate statuses may be skipped). Rapid successive updates produce one event per change.

## 4.2 Lead submission endpoint

- Use `partnerLeadSubmit` when you need the full lead pipeline (Spruce job submission and downstream processing for **heat**, or OpenSolar + solar pipeline when `leadType`/`projectType` is `solar`).
- **`leadType` is required** (`heat` / `heat_pump` or `solar` / `pv`). Omitting it returns HTTP 400 — there is no heat default.
- This endpoint requires partner API key auth.
- It supports direct or wrapped payload (`data`) formats.
- It applies the same partner rate limits.
- EPC identifier note: use certificate number/RRN (`epcData.epcCertificateNumber`) for heat leads.
- OpenSolar URLs may be supplied on solar leads but are **not** returned in the API response.
- Full payload and response spec: [Partner-Lead-Submit-API.md](./Partner-Lead-Submit-API.md)

## 4.2.1 Lead contact update endpoint

- Use `updateLeadCustomer` when you already have a `leadId` and need to change **customer** name, email, phone, and/or **callback** preferences.
- **Method:** `PATCH` only.
- Requires the same partner API key; the lead must belong to the authenticated partner.
- Updates customer details on the lead.
- Full spec: [updateLeadCustomer.md](./updateLeadCustomer.md)

## 4.2.2 Discover / reconcile leads

- Use **GET `/leads`** to list or fetch partner-scoped leads and read Installio `sales_status` / `sales_phase`.
- Full spec: [partnerGetLeads.md](./partnerGetLeads.md)

## 4.3 Web app: set partner `webhookUrl`

Your web app includes an input field where a partner can set the destination URL for partner status webhooks.

Recommended guidance text for UI:

- Label: **Webhook URL**
- Help text: **Enter your public HTTPS endpoint to receive `job.status_changed` and `sales.status_changed` events.**
- Validation: **Must be a valid `https://` URL reachable from the public internet.**
- Example value: `https://partner.example.com/installio/webhooks`

Suggested partner-facing note:

> We send `POST` requests with JSON payload whenever OMS detects a job status or sales status change.  
> Distinguish events with `event_type`. Your endpoint should return HTTP `2xx` quickly (within 8 seconds timeout window).

![alt text here](https://gist.github.com/user-attachments/assets/ac87272c-0ded-4965-933e-1e667b49b8de)

---

## 5. Payload sent to partner `webhookUrl`

Event types currently emitted:

- `job.status_changed`
- `sales.status_changed`

### 5.1 `job.status_changed`

```json
{
  "event_type": "job.status_changed",
  "event_id": "uuid",
  "occurred_at": "2026-05-05T08:00:00.000Z",
  "job_id": "string-or-null",
  "old_status": "string-or-null",
  "new_status": "string-or-null",
  "lead_id": "optional-string",
  "project_id": "optional-string"
}
```

### 5.2 `sales.status_changed`

```json
{
  "event_type": "sales.status_changed",
  "event_id": "uuid",
  "occurred_at": "2026-05-05T08:00:00.000Z",
  "lead_id": "string",
  "sales_status": "survey_booked",
  "sales_phase": "survey",
  "old_sales_status": "new",
  "new_sales_status": "survey_booked",
  "old_sales_phase": "new",
  "new_sales_phase": "survey",
  "old_status": "new",
  "new_status": "survey_booked",
  "project_id": "optional-string"
}
```

Supported `sales_status` values (fine-grain): `new`, `attempted_contact`, `contacted`, `consultation_booked`, `consultation_completed`, `survey_required`, `survey_booked`, `survey_in_progress`, `survey_completed`, `quote_in_progress`, `proposal_sent`, `proposal_accepted`, `validation_survey_booked`, `validation_survey_completed`, `validation_in_progress`, `validation_completed`, `won`, `closed_lost`.

Supported `sales_phase` values (coarse / partner default): `new`, `qualifying`, `survey`, `quote`, `validation`, `won`, `lost`.

Notes:

- Both events are delivered to the same partner `webhookUrl` subscription(s).
- `old_status` / `new_status` mirror `old_sales_status` / `new_sales_status` for compatibility.
- New subscriptions default to both event types; legacy job-only subscriptions also receive sales status on the same URL.
- Delivery is best effort to active partner webhook targets.
- Partners should key handlers on `event_type` and treat delivery as at-least-once (use `event_id` for idempotency if needed).

---

## 6. Rate limiting

Rate limits are evaluated per partner (or overridden per API key when configured).

Limits:

- Hourly cap: `maxRequestsPerHour`
- Daily cap: `maxRequestsPerDay`

Behavior:

- Exceeded hourly limit -> `429` with `Rate limit exceeded (hour)`
- Exceeded daily limit -> `429` with `Rate limit exceeded (day)`
- If rate limiter storage is temporarily unavailable, request may continue with warning `rate_limiter_unavailable`

---

## 7. Error handling

Common response structure:

```json
{
  "success": false,
  "error": "Human-readable reason"
}
```

Typical status codes:

| HTTP  | Meaning                                |
| ----- | -------------------------------------- |
| `400` | Invalid JSON or invalid request fields |
| `401` | Missing/invalid/disabled API key       |
| `403` | Partner mismatch or disabled partner   |
| `404` | Partner or resource not found          |
| `405` | Method not allowed                     |
| `429` | Rate limit exceeded                    |
| `500` | Internal server error                  |

Integration guidance:

- Treat non-2xx as failures and log full body for diagnostics.
- Implement exponential backoff + jitter for retryable calls.
- Include request correlation IDs in your own logs to trace integration issues.

---

## 8. Integration checklist

1. Obtain partner API key and target environment URL.
2. Integrate `partnerLeadSubmit` for lead submissions.
3. Optionally use GET `/leads` to reconcile Installio `sales_status` / `sales_phase`.
4. Add partner `webhookUrl` in your web app settings UI.
5. Configure your partner `webhookUrl` endpoint to receive `job.status_changed` and `sales.status_changed` payloads.
6. Add monitoring for `429` and `5xx` responses.
7. Validate behavior in dev before production rollout.

---

## 9. Support

For API keys, partner enablement, endpoint URLs, or rate limit updates, contact your Installio/Breengy platform administrator.
