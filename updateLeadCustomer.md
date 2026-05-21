# Update Lead Customer API

**Version:** 1.0  
**Function:** `updateLeadCustomer`  
**Purpose:** Update customer contact details (name, email, phone) and/or callback preferences (`callbackRequest`) on an existing lead created via the Partner API or widget. Optionally syncs those changes to HubSpot when the lead was previously pushed to CRM.

**Related:** Uses the **same partner API keys** as [Partner Lead Submit](./Partner-Lead-Submit-API.md). The `leadId` must come from a prior `partnerLeadSubmit` or `partnerEstimateSubmit` response (or another flow that created a document in the `leads` collection for your partner).

**Also see:** [Partner API overview](./Partner%20API%20Overview.md) (environments, auth, rate limits, errors).

---

## 1. When to use this endpoint

| Scenario                                                      | Endpoint                                 |
| ------------------------------------------------------------- | ---------------------------------------- |
| Create a new lead + Spruce job + HubSpot                      | `partnerLeadSubmit`                      |
| Create a lead + estimate only (no Spruce job)                 | `partnerEstimateSubmit`                  |
| **Correct customer name / email / phone on an existing lead** | **`updateLeadCustomer`**                 |
| **Update callback preferences on an existing lead**           | **`updateLeadCustomer`** (same endpoint) |

Use **`updateLeadCustomer`** after you have a `leadId` and the customer’s contact details and/or callback preferences have changed.

This endpoint does **not** change property, EPC, estimate, or Spruce job data—only `customer` and/or `callbackRequest` on the lead document.

---

## 2. Endpoint and method

- **Method:** `PATCH` (only; `POST` returns **405**)
- **Content-Type:** `application/json`

**Development (example):**

```
https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/updateLeadCustomer
```

**Production (example):**

```
https://europe-west2-co-pilot-b7f8e.cloudfunctions.net/updateLeadCustomer
```

**Local emulator (example):**

```
http://127.0.0.1:5001/co-pilot-dev-f762b/europe-west2/updateLeadCustomer
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

| Result                                                    | HTTP    |
| --------------------------------------------------------- | ------- |
| Missing / invalid key                                     | **401** |
| Disabled key                                              | **401** |
| Optional `partnerId` in body does not match key’s partner | **403** |
| Partner disabled in config                                | **403** |

---

## 4. Request body

### 4.1 Required fields

| Field    | Type   | Description                                                                                                        |
| -------- | ------ | ------------------------------------------------------------------------------------------------------------------ |
| `leadId` | string | Firestore document ID of the lead (non-empty, trimmed). Always at the **root** of the JSON body—not inside `data`. |

### 4.2 Customer fields (partial update)

Send **at least one** customer field **or** callback payload per request (see §4.3). Omitted customer fields are left unchanged on the lead.

**Widget-style names (root or under `data`):**

| Field               | Type   | Validation                                                                                                                                                                   |
| ------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `customerEmail`     | string | Valid email (`^[^\s@]+@[^\s@]+\.[^\s@]+$`); cannot be empty if sent                                                                                                          |
| `customerPhone`     | string | Non-empty if sent                                                                                                                                                            |
| `customerFirstName` | string | Non-empty if sent                                                                                                                                                            |
| `customerLastName`  | string | Non-empty if sent                                                                                                                                                            |
| `customerName`      | string | Full name; split into first token = first name, remainder = last name (same as widget). **Overrides** `customerFirstName` / `customerLastName` when sent in the same request |

**Nested object (root or under `data`):**

```json
"customer": {
  "email": "jane.smith@example.com",
  "phone": "07123456789",
  "firstName": "Jane",
  "lastName": "Smith",
  "name": "Jane Smith"
}
```

`customer.name` behaves like `customerName`.

### 4.3 Callback fields (`callbackRequest`)

Same shape and aliases as [Partner Lead Submit](./partnerLeadSubmit.md) §3.7. When provided, the whole `callbackRequest` object on the lead is **replaced** with the normalized value (including a fresh `submittedAt`).

**Nested object (root or under `data`):**

```json
"callbackRequest": {
  "questionsForCall": "Please call about heat pump sizing",
  "preferredCallTimeSlots": ["9-12", "14-16"],
  "preferredCallDays": ["monday", "wednesday"]
}
```

Snake-case aliases (`callback_request`, `questions_for_call`, `preferred_call_days`, `preferred_call_time_slots`) are accepted. Flat callback fields at root or under `data` (without nesting) are also accepted.

You may send **only** `callbackRequest`, **only** customer fields, or both in one `PATCH`.

### 4.4 Payload layouts

1. **Direct** — `leadId` and customer fields at the root.
2. **Wrapped** — customer fields under `data`; `leadId` stays at root.

```json
{
  "leadId": "abc123xyz",
  "data": {
    "customerEmail": "new@example.com",
    "customerPhone": "07987654321"
  }
}
```

3. **Optional `partnerId`** at root — if present, must match the partner attached to the API key.

### 4.5 What is stored

The service merges your patch into the lead’s `customer` object:

```json
{
  "firstName": "string",
  "lastName": "string",
  "email": "string",
  "phone": "string"
}
```

When `callbackRequest` is sent:

```json
{
  "questionsForCall": "string",
  "preferredCallTimeSlots": ["string"],
  "preferredCallDays": ["string"],
  "submittedAt": "ISO-8601 string"
}
```

`updatedAt` is set on the lead document.

---

## 5. HubSpot sync

If the lead was previously synced to HubSpot via the full lead pipeline, this endpoint **also** updates HubSpot in the same request:

| Condition                                                                            | HubSpot behaviour                                                                                                                                                                                                                    |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `hubspot.status === "submitted"` and `hubspot.dealId` present                        | PATCH HubSpot **contact** (email, firstname, lastname, phone) and **deal** (structured deal properties derived from the lead, including `preferred_days`, `preferred_times`, `callback_questions` when `callbackRequest` is present) |
| Lead not yet in HubSpot (e.g. estimate-only submit, or Spruce/HubSpot still pending) | Firestore updated only; response includes `hubspot.skipped: true`, `reason: "lead_not_in_hubspot"`                                                                                                                                   |
| `HUBSPOT_API_KEY` not configured on the function                                     | Firestore updated; HubSpot skipped with `reason: "hubspot_api_key_missing"`                                                                                                                                                          |

**Typical HubSpot path for partner leads:**

1. `partnerLeadSubmit` creates the lead and submits to Spruce.
2. Firestore trigger `onLeadHubSpotPush` creates contact + deal when Spruce completes.
3. Later, `updateLeadCustomer` PATCHes Firestore and HubSpot when contact details change.

`partnerEstimateSubmit` alone does **not** create HubSpot records; updates to those leads will return `lead_not_in_hubspot` until a full submit/sync has run.

The response includes a `hubspot` object so you can see whether CRM sync ran (see section 6).

---

## 6. Responses

### 6.1 Success (200)

```json
{
  "success": true,
  "leadId": "abc123xyz",
  "customer": {
    "firstName": "Jane",
    "lastName": "Smith",
    "email": "jane.smith@example.com",
    "phone": "07123456789"
  },
  "callbackRequest": {
    "questionsForCall": "Please call after 5pm",
    "preferredCallTimeSlots": ["9-12"],
    "preferredCallDays": ["tuesday", "wednesday"],
    "submittedAt": "2026-05-21T12:00:00.000Z"
  },
  "hubspot": {
    "synced": true,
    "skipped": false,
    "contactId": "12345",
    "dealId": "67890",
    "contactOk": true,
    "dealOk": true,
    "error": null
  }
}
```

**HubSpot skipped** (lead not in CRM yet):

```json
{
  "success": true,
  "leadId": "abc123xyz",
  "customer": {
    "firstName": "Jane",
    "lastName": "Smith",
    "email": "jane@example.com",
    "phone": "07123456789"
  },
  "hubspot": {
    "synced": false,
    "skipped": true,
    "reason": "lead_not_in_hubspot"
  }
}
```

**HubSpot attempted but failed** (Firestore update still succeeded):

```json
{
  "success": true,
  "leadId": "abc123xyz",
  "customer": { "...": "..." },
  "hubspot": {
    "synced": false,
    "skipped": false,
    "contactId": "12345",
    "dealId": "67890",
    "contactOk": false,
    "dealOk": true,
    "error": "contact_update_failed"
  }
}
```

Optional `warnings` array (e.g. rate limiter degraded): `"warnings": ["rate_limiter_unavailable"]`.

### 6.2 Error responses

| HTTP    | `error` (typical)                                           | When                                                 |
| ------- | ----------------------------------------------------------- | ---------------------------------------------------- |
| **400** | `Invalid or missing leadId`                                 | No `leadId`                                          |
| **400** | `Invalid email address` / `customerEmail cannot be empty`   | Bad or empty email                                   |
| **400** | `Invalid callbackRequest`                                   | `callbackRequest` is not a JSON object when provided |
| **400** | `No fields to update`                                       | No customer or callback fields sent                  |
| **401** | `Missing Authorization header` / `Invalid API key`          | Auth failure                                         |
| **403** | `Partner mismatch` / `Lead does not belong to this partner` | Wrong partner or lead ownership                      |
| **403** | `Partner is disabled`                                       | Partner turned off                                   |
| **404** | `Lead not found`                                            | Unknown `leadId`                                     |
| **404** | `Partner not found`                                         | Invalid partner config                               |
| **405** | `Method not allowed`                                        | Not `PATCH`                                          |
| **429** | `Rate limit exceeded (hour)` / `(day)`                      | Partner quota                                        |
| **500** | `Internal server error`                                     | Unexpected failure                                   |

Example **404**:

```json
{
  "success": false,
  "error": "Lead not found",
  "leadId": "unknown-id"
}
```

Example **400**:

```json
{
  "success": false,
  "error": "No fields to update",
  "message": "Provide at least one customer field and/or callbackRequest (or flat callback fields)"
}
```

---

## 7. Rate limiting

The same **per-partner** limits apply as for Partner Lead Submit and Partner Estimate Submit (hourly and daily caps on the partner or API key record). **429** is returned when a limit is exceeded.

---

## 8. CORS

`OPTIONS` requests return **204** for browser preflight. Other methods use the shared widget CORS handler.

---

## 9. Examples

### 9.1 Update all contact fields (cURL)

```bash
curl -sS -X PATCH \
  'https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/updateLeadCustomer' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_PARTNER_API_KEY' \
  -d '{
    "leadId": "YOUR_LEAD_ID",
    "customerName": "Jane Smith",
    "customerEmail": "jane.smith@example.com",
    "customerPhone": "07123456789"
  }'
```

### 9.2 Partial update (phone only)

```bash
curl -sS -X PATCH \
  'https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/updateLeadCustomer' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_PARTNER_API_KEY' \
  -d '{
    "leadId": "YOUR_LEAD_ID",
    "customerPhone": "07987654321"
  }'
```

### 9.3 Local emulator

```bash
curl -sS -X PATCH \
  'http://127.0.0.1:5001/co-pilot-dev-f762b/europe-west2/updateLeadCustomer' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_PARTNER_API_KEY' \
  -d '{
    "leadId": "YOUR_LEAD_ID",
    "customerFirstName": "Jane",
    "customerLastName": "Smith",
    "customerEmail": "jane.smith@example.com",
    "customerPhone": "07123456789"
  }'
```

### 9.4 Callback preferences only

```bash
curl -sS -X PATCH \
  'http://127.0.0.1:5001/co-pilot-dev-f762b/europe-west2/updateLeadCustomer' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_PARTNER_API_KEY' \
  -d '{
    "leadId": "YOUR_LEAD_ID",
    "callbackRequest": {
      "questionsForCall": "Please call about heat pump sizing",
      "preferredCallTimeSlots": ["9-12", "14-16"],
      "preferredCallDays": ["monday", "wednesday"]
    }
  }'
```

### 9.5 Customer + callback in one request

```bash
curl -sS -X PATCH \
  'http://127.0.0.1:5001/co-pilot-dev-f762b/europe-west2/updateLeadCustomer' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_PARTNER_API_KEY' \
  -d '{
    "leadId": "YOUR_LEAD_ID",
    "customerPhone": "07987654321",
    "callbackRequest": {
      "questionsForCall": "Ring after 3pm",
      "preferredCallDays": ["tuesday"],
      "preferredCallTimeSlots": ["14-16"]
    }
  }'
```

### 9.6 Nested `customer` object

```bash
curl -sS -X PATCH \
  'https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/updateLeadCustomer' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_PARTNER_API_KEY' \
  -d '{
    "leadId": "YOUR_LEAD_ID",
    "customer": {
      "email": "jane.smith@example.com",
      "phone": "07123456789",
      "firstName": "Jane",
      "lastName": "Smith"
    }
  }'
```

Replace `YOUR_PARTNER_API_KEY`, `YOUR_LEAD_ID`, and base URLs with your environment values.

---

## 10. Integration notes

1. **Store `leadId`** from `partnerLeadSubmit` / `partnerEstimateSubmit` responses if you may need to correct contact details later.
2. **Lead IDs** are Firestore auto-generated strings (e.g. `eEUM0ICKjtPATjLbis57`), not UUIDs, unless your integration uses a custom ID scheme.
3. **Idempotency:** Sending the same values twice is safe; the lead and HubSpot contact are overwritten with the same data.
4. **Email changes:** If HubSpot sync is active, the contact record is PATCHed by `hubspot.contactId`; ensure your CRM processes allow email updates on existing contacts.
5. **Downstream trigger:** A Firestore `onLeadHubSpotPush` update may also run after this write; behaviour is aligned with the explicit sync in this endpoint.

---

## 11. Support

For API keys, partner enablement, URL confirmation, or quota changes, contact your **Installio / Breengy platform administrator**. For creating leads and full payload semantics, see [Partner Lead Submit](./Partner-Lead-Submit-API.md) and [Partner API overview](./Partner%20API%20Overview.md).
