# Partner webhook subscriptions

**Version:** 1.0  
**Function:** `partnerWebhookSubscriptions`  
**Methods:** `GET`, `POST`, `PUT`  
**Purpose:** Set the HTTPS URL that receives partner webhooks, and read or rotate the signing secret used to verify those deliveries.

**Related:** Same partner API key as [Partner Lead Submit](./Partner-Lead-Submit-API.md). Event payloads are in the [Partner API overview](./Partner%20API%20Overview.md).

The webhook URL is not a field in OMS, and it is not sent when you create a lead.

---

## 1. Endpoint and method

- **Auth:** `Authorization: Bearer <partner-api-key>` (same formats as the other Partner API endpoints)
- **Content-Type:** `application/json` for `POST` and `PUT`
- **URL:** public `https://` only. `http://`, localhost, and `.local` hosts are rejected.

**Development (example):**

```
https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/partnerWebhookSubscriptions
```

**Production (example):**

```
https://europe-west2-co-pilot-b7f8e.cloudfunctions.net/partnerWebhookSubscriptions
```

---

## 2. Create — `POST`

```json
{
  "webhookUrl": "https://partner.example.com/installio/webhooks",
  "description": "ECS status listener"
}
```

| Field | Required | Notes |
| ----- | -------- | ----- |
| `webhookUrl` | yes | Public `https://` URL |
| `enabled` | no | Defaults to `true`. `false` pauses delivery |
| `description` | no | Stored label. Empty becomes `null` |
| `eventTypes` | no | Omit to store `job.status_changed` and `sales.status_changed`. A custom array replaces that default |

You cannot choose `signingSecret`. Installio generates it.

```json
{
  "success": true,
  "subscription": {
    "id": "subscription-id",
    "webhookUrl": "https://partner.example.com/installio/webhooks",
    "enabled": true,
    "eventTypes": ["job.status_changed", "sales.status_changed"],
    "description": "ECS status listener",
    "signingSecret": "whsec_…",
    "createdAt": "2026-11-05T12:00:00.000Z",
    "updatedAt": "2026-11-05T12:00:00.000Z"
  }
}
```

Store `signingSecret` on your server. Treat it like a password. It is returned again by `GET`, so anyone with the partner API key can read it.

---

## 3. List — `GET`

Returns `{ "success": true, "subscriptions": [ … ] }`, newest first. Each item has the same fields as create, including `signingSecret`.

A subscription created before signing has no secret until the first `GET` or the next delivery. That call writes one secret and returns it. Read it before you start rejecting unsigned deliveries.

---

## 4. Update — `PUT`

Send `subscriptionId` plus at least one change.

```json
{
  "subscriptionId": "subscription-id",
  "webhookUrl": "https://partner.example.com/installio/webhooks-v2",
  "enabled": true,
  "rotateSigningSecret": true
}
```

| Field | Notes |
| ----- | ----- |
| `subscriptionId` | Required |
| `webhookUrl` | Public `https://` URL |
| `enabled` | `false` pauses delivery without deleting the subscription |
| `description` | Pass `null` or `""` to clear it |
| `eventTypes` | Replaces the stored list. An empty array resets to the default |
| `rotateSigningSecret` | `true` issues a new `signingSecret` immediately. The previous secret stops verifying |

A `signingSecret` field in the body is ignored.

The response is `{ "success": true, "subscription": { … } }` with the current secret.

---

## 5. Verify a delivery

Installio `POST`s JSON to `webhookUrl`. Headers:

| Header | Value |
| ------ | ----- |
| `Content-Type` | `application/json` |
| `User-Agent` | `Installio-Partner-Webhook/1.0` |
| `X-Installio-Timestamp` | Unix time in seconds |
| `X-Installio-Signature` | `t=<timestamp>,v1=<hex>` |

`v1` is hex HMAC-SHA256 of the string `${timestamp}.${rawBody}`, keyed with `signingSecret`. `rawBody` is the exact request body. Do not parse and re-serialize the JSON before verifying. The secret is not placed in the URL or the body.

Reject a timestamp more than 5 minutes off your clock. Compare the hex with a constant-time compare. Return any HTTP `2xx` within 8 seconds. Other statuses are logged as delivery failures. There is no automatic retry.

```js
const crypto = require("crypto");

function verifyInstallioWebhook(signingSecret, rawBody, timestampHeader, signatureHeader) {
  const timestamp = String(timestampHeader || "");
  const ageSeconds = Math.abs(Math.floor(Date.now() / 1000) - Number(timestamp));
  if (!Number.isFinite(ageSeconds) || ageSeconds > 300) return false;

  const expected = crypto
    .createHmac("sha256", signingSecret)
    .update(`${timestamp}.${rawBody}`)
    .digest("hex");
  const match = String(signatureHeader || "").match(/(?:^|,)v1=([0-9a-f]+)/i);
  if (!match) return false;

  const a = Buffer.from(expected, "utf8");
  const b = Buffer.from(match[1].toLowerCase(), "utf8");
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}
```

Distinguish events with `event_type`. Treat delivery as at-least-once and use `event_id` if you need idempotency.

---

## 6. Errors

| HTTP | Meaning |
| ---- | ------- |
| `400` | Missing or non-HTTPS `webhookUrl`, or `PUT` with no fields to change |
| `401` | Missing, invalid, or disabled API key |
| `403` | Partner mismatch, or the partner is disabled |
| `404` | Unknown `subscriptionId` |
| `405` | Method other than `GET`, `POST`, or `PUT` |
| `429` | Rate limit exceeded |
| `500` | Internal error |
