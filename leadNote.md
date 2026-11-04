# Lead Note API

**Version:** 1.0  
**Function:** `leadNote`  
**Method:** `POST`  
**Purpose:** Send a transactional update for an existing lead. Installio stores the note and files it on the matching sales record. The response does not include any CRM ids.

**Related:** Uses the **same partner API keys** as [Partner Lead Submit](./Partner-Lead-Submit-API.md). The `leadId` must come from a prior `partnerLeadSubmit` or `partnerEstimateSubmit` response (or another flow that created a lead for your partner).

**Also see:** [Partner API overview](./Partner%20API%20Overview.md) (environments, auth, rate limits, errors).

---

## 1. When to use this endpoint

| Scenario | Endpoint |
| -------- | -------- |
| Create a new lead | `partnerLeadSubmit` or `partnerEstimateSubmit` |
| Change customer contact, callback, or `outreachAllowed` | `updateLeadCustomer` |
| **Send a subject and message about an existing lead** | **`leadNote`** |

Use **`leadNote`** when you already have a `leadId` and need to pass a transactional update (for example a signed contract or a booked survey). Installio keeps the note. A missing downstream sales record does not fail the call; the note is filed once that record exists.

This endpoint does **not** create a lead, change customer details, or change sales status.

---

## 2. Endpoint and method

- **Method:** `POST` (only; other methods return **405**)
- **Content-Type:** `application/json`

**Development (example):**

```
https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/leadNote
```

**Production (example):**

```
https://europe-west2-co-pilot-b7f8e.cloudfunctions.net/leadNote
```

**Local emulator (example):**

```
http://127.0.0.1:5001/co-pilot-dev-f762b/europe-west2/leadNote
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
| Optional `partnerId` in body does not match key’s partner | **403** |
| Partner disabled in config | **403** |
| Lead belongs to another partner | **403** |

---

## 4. Request body

All fields are required and sit at the **root** of the JSON body. There is no wrapped `data` payload.

| Field | Type | Required | Notes |
| ----- | ---- | -------- | ----- |
| `leadId` | string | yes | Also accepted as `lead_id`. Non-empty, trimmed. Must belong to the authenticated partner. |
| `subject` | string | yes | Non-empty, trimmed. Max 300 characters. |
| `message` | string | yes | Non-empty, trimmed. Max 20,000 characters. |
| `partnerId` | string | no | If present, must match the partner attached to the API key. |

```json
{
  "leadId": "abc123",
  "subject": "Customer signed — 221 Lowfield Street, Dartford",
  "message": "Ivan Kolopelnyk has signed the contract for 221 Lowfield Street, Dartford, Kent."
}
```

---

## 5. Responses

### 5.1 Success (200)

```json
{
  "success": true,
  "accepted": true,
  "leadId": "abc123",
  "noteId": "generated-id"
}
```

`accepted: true` means Installio stored the note. It does not mean a sales record was already on file. Optional `warnings` array (for example when the rate limiter is degraded): `"warnings": ["rate_limiter_unavailable"]`.

The response never includes CRM record ids.

### 5.2 Error responses

Validation returns the first problem only.

| HTTP | `error` (typical) | When |
| ---- | ----------------- | ---- |
| **400** | `Invalid request` | Body is missing or not a JSON object |
| **400** | `Invalid or missing leadId` | No `leadId` / `lead_id` |
| **400** | `Invalid or missing subject` | No subject |
| **400** | `subject must be at most 300 characters` | Subject too long |
| **400** | `Invalid or missing message` | No message |
| **400** | `message must be at most 20000 characters` | Message too long |
| **401** | `Missing Authorization header` / `Invalid API key` | Auth failure |
| **403** | `Partner mismatch` | Body `partnerId` does not match the key |
| **403** | `Partner is disabled` | Partner turned off |
| **403** | `Lead does not belong to this partner` | Lead owned by another partner |
| **404** | `Lead not found` | Unknown `leadId` |
| **404** | `Partner not found` | Invalid partner config |
| **405** | `Method not allowed` | Not `POST` |
| **429** | `Rate limit exceeded (hour)` / `(day)` | Partner quota |
| **500** | `Internal server error` | Unexpected failure |

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
  "error": "Invalid or missing subject"
}
```

---

## 6. Rate limiting

The same **per-partner** limits apply as for Partner Lead Submit (hourly and daily caps on the partner or API key record). **429** is returned when a limit is exceeded.

---

## 7. CORS

`OPTIONS` requests return **204** for browser preflight. Other methods use the shared widget CORS handler.

---

## 8. Example

```bash
curl -sS -X POST \
  'https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/leadNote' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_PARTNER_API_KEY' \
  -d '{
    "leadId": "YOUR_LEAD_ID",
    "subject": "Customer signed — 221 Lowfield Street, Dartford",
    "message": "Ivan Kolopelnyk has signed the contract for 221 Lowfield Street, Dartford, Kent."
  }'
```
