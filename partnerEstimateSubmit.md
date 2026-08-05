# Partner Heat Pump Estimate API

**Version:** 1.0  
**Function:** `partnerEstimateSubmit`  
**Purpose:** Request a heat pump / heat-loss estimate from server-side systems (for example ECS or other partner backends). The service validates the payload, calls the estimate engine, stores a lead record in Firestore, and returns a structured response.

**Related:** Uses the **same partner API keys** as the [Partner Lead Submit API](./Partner-Lead-Submit-API.md). Payload shape matches the public estimator widget, plus optional **ECS integration** fields described in section 4.

**Also see:** [Partner API overview](./Partner%20API%20Overview.md) (environments, auth, rate limits, errors, endpoint choice).

---

## 1. How this differs from Partner Lead Submit

|                 | **partnerEstimateSubmit** | **partnerLeadSubmit**                  |
| --------------- | ------------------------- | -------------------------------------- |
| Spruce CRM job  | Not created               | Created                                |
| Primary outcome | Estimate JSON + `leadId`  | Lead + Spruce job + estimate           |

Use **partnerEstimateSubmit** when you only need an estimate and internal persistence. Use **partnerLeadSubmit** when you need a full lead pipeline (Spruce job and downstream processing).

---

## 2. Endpoint and method

- **Method:** `POST`
- **Content-Type:** `application/json`

**Development (example):**

```
https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/partnerEstimateSubmit
```

**Production (example):**

```
https://europe-west2-co-pilot-b7f8e.cloudfunctions.net/partnerEstimateSubmit
```

**Local emulator (example):** replace project and port if your `firebase.json` differs.

```
http://127.0.0.1:5001/<project-id>/europe-west2/partnerEstimateSubmit
```

Confirm the exact URL with your platform administrator before integration.

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

Missing or invalid keys receive **401**. Disabled keys receive **401** with an appropriate error message.

---

## 4. Request body

### 4.1 Structure

The body is a single JSON object. Two layouts are supported:

1. **Direct:** Widget fields at the **root** of the JSON (plus optional `ecs`, `partnerId`).
2. **Wrapped:** Widget fields under **`data`**, optional **`partnerId`** at root (must match the key’s partner if supplied).

The widget field definitions (customer, property, EPC, qualifying questions, enums) are the **same** as in [Partner Lead Submit – Request Body](./Partner-Lead-Submit-API.md#3-request-body). This document does not duplicate the full enum lists; refer to that spec for allowed values.

### 4.2 Customer fields (required)

Validation matches the widget contract:

- `customerName` — non-empty string
- `customerEmail` — valid email
- `customerPhone` — non-empty string

### 4.3 Estimate prerequisites

After mapping (including EPC-derived values where applicable), the estimate service requires the following **Spruce estimate** inputs to be present and non-empty. If any are missing, the API returns **400** with `missingEstimateFields` (no lead is created).

Typical keys in error responses (internal Spruce field names):

`built_form`, `floor_area_m2`, `fuel_type`, `loft_insulation`, `num_bedrooms`, `postcode`, `property_type`, `wall_type`, `window_type`

**Happy path (EPC-assisted):** supply `hasEPC: "yes"` and a populated `epcData` object so missing manual fields can be filled from certificate data where the mapper allows.

**Manual path:** supply postcode, property type, built form / description, floor area, bedrooms, fuel, wall (and cavity / external insulation as required), windows, and roof / loft insulation so the mapped payload is complete.

### 4.3.1 Indicative quote: field priority and fallback strategy

For early-stage indicative quotes, prioritize these fields in this order:

1. `postcode` (drives climate assumptions and external datasets)
2. `floorArea` + `floorAreaUnit`
3. `propertyType` + `propertyDescription` (built form)
4. `bedrooms` and `floors`
5. `fuelType`
6. `wallType` (+ insulation qualifier)
7. `windowType`
8. `roofInsulation`

Recommended fallback approach when EPC narratives are inconsistent (for example wall descriptions):

- Prefer structured fields from `GET /api/certificate` (for example `sap_building_parts.*`) over free-text narratives.
- If only narratives are available, normalize to lowercase and map by keywords (for example `cavity`, `solid brick`, `solid stone`, `timber`).
- For cavity walls, keep insulation as a separate decision (`filled` vs `unfilled`) rather than inferring from weak text fragments.
- If certainty is low, send an explicit unknown-safe value and avoid overfitting with fragile parsing.
- If you have an RRN/certificate number, send it (`epcCertificateNumber`) so Spruce can enrich with certificate-backed defaults.

### 4.4 ECS / integration metadata (optional, INS-657)

These fields are **optional**. They are stored on the created lead and echoed in the JSON response. You may send them nested under **`ecs`** or use the root-level aliases below.

| Semantic field            | Under `ecs`                              | Root-level aliases                            |
| ------------------------- | ---------------------------------------- | --------------------------------------------- |
| External identifier       | `externalId` or `external_id`            | `ecsExternalId`, `ecs_external_id`            |
| Correlation / trace id    | `correlationId` or `correlation_id`      | `ecsCorrelationId`, `ecs_correlation_id`      |
| Installio job reference   | `installioJobRef` or `installio_job_ref` | `ecsInstallioJobRef`, `ecs_installio_job_ref` |
| Free-form metadata object | `metadata`                               | `ecsMetadata`                                 |

`metadata` must be a JSON object if provided.

---

## 5. Success response

**HTTP 200** — The lead was created and a record was written. The estimate call may still fail upstream; check **`estimateSuccess`**.

```json
{
  "success": true,
  "partnerId": "your-partner-id",
  "leadId": "firestore-document-id",
  "inputPath": "epc",
  "ecs": {
    "externalId": "string-or-null",
    "correlationId": "string-or-null",
    "installioJobRef": "string-or-null",
    "metadata": {}
  },
  "estimate": {},
  "estimateSummary": {
    "url": "string-or-null",
    "estimateCount": 0,
    "totalHeatLossW": null,
    "totalPriceIncludingGrantsPence": null,
    "customer_discount_rate_percent": 0.15,
    "discounted_total_price_including_grants_pence": null
  },
  "estimateSuccess": true,
  "estimateError": null,
  "warnings": []
}
```

- **`inputPath`:** `"epc"` if `hasEPC === "yes"` and non-empty `epcData`; otherwise `"manual"`.
- **`estimate`:** Full JSON returned by the estimate service on success, **plus** contractual ECS customer discount fields on each element of **`estimate.estimates`** (see below); **`null`** if **`estimateSuccess`** is false.
- **`estimateSummary`:** Small convenience object (first estimate row when present); **`null`** if the estimate failed.
- **`warnings`:** May include `rate_limiter_unavailable` if the rate limiter failed open (request still processed).

### 5.1 Customer discount (ECS heat-pump pricing)

On success, each object in **`estimate.estimates`** includes:

| Field | Description |
| ----- | ----------- |
| **`customer_discount_rate_percent`** | Decimal fraction applied to the partner price **after** grants (e.g. `0.15` = 15%). Default **0.15** unless your partner document sets **`customer_discount_rate_percent`** in Firestore (platform team updates this when the contract changes). |
| **`discounted_total_price_including_grants_pence`** | Integer pence: `total_price_including_grants_pence * (1 - customer_discount_rate_percent)`, rounded to the nearest penny. **`null`** if the source price is missing. |

The same two keys are echoed on **`estimateSummary`** for the first estimate row.

**Contract context:** “Total Installation Cost” (gross price to the referred client for system and labour, inclusive of hardware, **exclusive of VAT and government grants**) corresponds to the estimate API’s pre-grant figures (e.g. **`total_price_excluding_grants_pence`**). The **discounted** figure above is computed from **`total_price_including_grants_pence`** (after grants) per the integration agreement.

---

## 6. Error responses

| HTTP | Typical cause                                                                                                           |
| ---- | ----------------------------------------------------------------------------------------------------------------------- |
| 400  | Invalid JSON body, bad customer fields, estimate prerequisites not met (`missingEstimateFields`), invalid payload shape |
| 401  | Missing / invalid / disabled API key                                                                                    |
| 403  | `partnerId` in body does not match key, or partner disabled                                                             |
| 404  | Partner configuration not found                                                                                         |
| 405  | Method other than POST                                                                                                  |
| 429  | Partner rate limit exceeded                                                                                             |
| 500  | Unexpected server error                                                                                                 |

Example **400** (estimate prerequisites):

```json
{
  "success": false,
  "error": "Missing required fields for estimate: postcode, wall_type",
  "missingEstimateFields": ["postcode", "wall_type"],
  "inputPath": "manual"
}
```

---

## 7. Rate limiting

The same **per-partner** limits apply as for Partner Lead Submit (hourly and daily caps configured on the partner or API key record). **429** is returned when a limit is exceeded.

---

## 8. Persistence

Each successful request creates a document in the **`leads`** collection with:

- Standard lead fields from the widget payload (`createLeadDocument`)
- **`submissionChannel`:** `"partner_estimate_api"`
- **`ecs`:** resolved integration object from section 4.4
- **`estimate`:** full estimate JSON when successful, including Spruce fields **plus** `customer_discount_rate_percent` and `discounted_total_price_including_grants_pence` on each `estimates` row (same shape as the HTTP `estimate` payload)
- **`estimateRequest`:** outcome metadata (`success`, `error`, `statusCode`, `inputPath`, `completedAt`, optional `rawResponse`)
- **`spruce.estimateUrl`:** report URL when available

`spruce.status` remains in a **non-submitted** state for this flow (estimate-only; no Spruce job is created).

---

## 9. Example: cURL (manual property path)

```bash
curl -sS -X POST \
  'https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/partnerEstimateSubmit' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_PARTNER_API_KEY' \
  -d '{
    "customerName": "Alex Example",
    "customerEmail": "alex.example@company.com",
    "customerPhone": "+447700900123",
    "address": "10 Example Street",
    "addressPostcode": "SW1A 1AA",
    "addressLat": "51.5014",
    "addressLng": "-0.1419",
    "hasEPC": "no",
    "propertyType": "house",
    "propertyDescription": "semi_detached",
    "floorArea": "120",
    "floorAreaUnit": "sqm",
    "bedrooms": "3",
    "bathrooms": "2",
    "floors": "2",
    "fuelType": "mains_gas",
    "wallType": "cavity_wall",
    "cavityWallInsulation": "filled",
    "windowType": "double_glazing",
    "roofInsulation": "150mm",
    "ecs": {
      "externalId": "partner-system-job-2025-001",
      "correlationId": "550e8400-e29b-41d4-a716-446655440000",
      "metadata": { "environment": "integration-test" }
    }
  }'
```

---

## 10. Example: wrapped payload with EPC hints

```bash
curl -sS -X POST \
  'https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/partnerEstimateSubmit' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_PARTNER_API_KEY' \
  -d '{
    "data": {
      "customerName": "Alex Example",
      "customerEmail": "alex.example@company.com",
      "customerPhone": "+447700900123",
      "address": "10 Example Street",
      "addressPostcode": "SW1A 1AA",
      "hasEPC": "yes",
      "epcData": {
        "epcCertificateNumber": "1700-1141-0422-4422-3253",
        "postcode": "SW1A 1AA",
        "address": "10 Example Street",
        "propertyType": "house",
        "builtForm": "semi_detached",
        "floorArea": 120,
        "wallConstruction": "cavity wall",
        "windowType": "double_glazed",
        "roofInsulation": "150mm",
        "mainFuel": "mains gas (not community)"
      },
      "propertyType": "house",
      "propertyDescription": "semi_detached",
      "bedrooms": "3",
      "fuelType": "mains_gas",
      "wallType": "cavity_wall",
      "cavityWallInsulation": "filled",
      "windowType": "double_glazing",
      "roofInsulation": "150mm"
    },
    "ecs": {
      "externalId": "epc-flow-001",
      "installioJobRef": "optional-reference"
    }
  }'
```

Replace URLs, **`YOUR_PARTNER_API_KEY`**, and EPC identifiers with values from your environment.

---

## 11. Support

For API keys, partner enablement, URL confirmation, or quota changes, contact your **Installio / Breengy platform administrator**. For payload field semantics and enums, use this document together with the **Partner Lead Submit** specification linked above.
