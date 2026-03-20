# Technical Specification: Partner Lead Submit API

**Version:** 1.0  
**Endpoint:** `partnerLeadSubmit`  
**Purpose:** Accept lead submissions from partner systems via API key authentication.

---

## 1. Overview

The Partner Lead Submit API lets you submit leads from your own systems—CRMs, websites, or internal tools—without embedding the widget. Send customer and property details in a single request and receive a lead ID, heat-loss estimate, and job reference.

**Use cases:** Integrate lead capture from your website forms, sync leads from your CRM, or automate submissions from other data sources.

**Authentication:** Each request requires a partner API key in the `Authorization` header. Keys are issued per partner—contact your administrator to obtain one.

**Response:** On success, you receive a unique lead ID, Spruce job details (UUID, URL, reference), and an optional heat-loss estimate. Use the lead ID to track or retrieve the lead later.

---

## 2. Request Specification

### 2.1 Method and URL

- **Method:** `POST`

**Sandbox (dev):**

```
https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/partnerLeadSubmit
```

**Production (prod):**

```
https://europe-west2-co-pilot-b7f8e.cloudfunctions.net/partnerLeadSubmit
```

### 2.2 Headers

```json
{
  "Content-Type": "application/json",
  "Authorization": "Bearer <partner-api-key>"
}
```

**Authorization** accepts any of:

```json
"Bearer <api-key>"
"ApiKey <api-key>"
"api-key <api-key>"
"<api-key>"
```

---

## 3. Request Body

### 3.1 Payload Structure

The body must be a JSON object. Two formats are supported:

**Direct format** — widget fields at root level.

**Wrapped format** — widget fields nested under `data`; optional `partnerId` at root for validation.

### 3.2 Required Fields

These fields are mandatory. Validation fails if missing or invalid.

```json
{
  "customerName": "string (non-empty, trimmed)",
  "customerEmail": "string (valid email: ^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$)",
  "customerPhone": "string (non-empty, trimmed)"
}
```

### 3.3 Optional Property Fields

```json
{
  "address": "string",
  "addressPostcode": "string",
  "addressLat": "number",
  "addressLng": "number",
  "addressUdprn": "string",
  "propertyType": "string",
  "propertyDescription": "string",
  "bedrooms": "number",
  "bathrooms": "number",
  "floors": "number",
  "floorArea": "number",
  "floorAreaUnit": "string",
  "fuelType": "string",
  "wallType": "string",
  "cavityWallInsulation": "string",
  "externalWallInsulation": "string",
  "windowType": "string",
  "roofInsulation": "string",
  "projectType": "string"
}
```

### 3.4 Optional EPC Fields

```json
{
  "hasEPC": "yes | no",
  "epcData": {
    "lmkKey": "string",
    "postcode": "string",
    "address": "string",
    "propertyType": "string",
    "builtForm": "string",
    "floorArea": "number",
    "wallConstruction": "string",
    "windowType": "string",
    "roofInsulation": "string",
    "mainFuel": "string"
  }
}
```

### 3.5 Optional Qualifying / Other Fields

```json
{
  "hearAboutUs": "string",
  "homeEnergy": "string",
  "tenure": "string",
  "externalSpace": "string",
  "cylinderSpace": "string",
  "renovating": "string",
  "goals": "string",
  "questionsForTeam": "string"
}
```

### 3.6 Top-Level Wrapper Fields (wrapped format only)

```json
{
  "partnerId": "string (optional; if present, must match API key's partner)",
  "data": {
    /* widget fields */
  }
}
```

---

## 4. Field Value Specifications (Enums)

### 4.1 propertyType

```json
["house", "flat", "bungalow"]
```

### 4.2 propertyDescription

```json
[
  "detached",
  "semi_detached",
  "semi-detached",
  "terrace",
  "mid-terrace",
  "end-terrace",
  "end_terrace"
]
```

Use `null` or omit for flats. Maps to Spruce `built_form`.

### 4.3 fuelType

```json
["mains_gas", "electric", "oil", "lpg", "coal", "wood", "other"]
```

`other` falls back to EPC data or `mains_gas`.

### 4.4 wallType

```json
["cavity_wall", "solid_brick", "solid_stone", "timber"]
```

- `cavity_wall` — requires `cavityWallInsulation`
- `solid_brick`, `solid_stone`, `timber` — require `externalWallInsulation`

### 4.5 cavityWallInsulation (when wallType = cavity_wall)

```json
[
  "insulated",
  "with insulation",
  "filled",
  "uninsulated",
  "unfilled",
  "not insulated",
  "cavity_wall_filled",
  "cavity_wall_unfilled"
]
```

Maps to Spruce: insulated variants → `cavity_wall_unfilled`; uninsulated → `cavity_wall_filled`.

### 4.6 externalWallInsulation (when wallType = solid_brick | solid_stone | timber)

```json
["internal", "external", "none", "idk", "i don't know"]
```

Maps to Spruce: `*_internal_insulation`, `*_external_insulation`, `*_uninsulated`, `*_unknown`.

### 4.7 windowType

```json
[
  "single",
  "single_glazed",
  "single_glazing",
  "double",
  "double_glazed",
  "double_glazing",
  "triple",
  "triple_glazed",
  "triple_glazing",
  "high_performance"
]
```

Default when omitted: `double_glazing`.

### 4.8 roofInsulation

```json
["none", "50mm", "100mm", "150mm", "200mm", "250mm_plus", "250+mm"]
```

Default when omitted: `100mm`.

### 4.9 floorAreaUnit

```json
["sqm", "sqft", "square feet", "ft²"]
```

Default: `sqm`.

### 4.10 hasEPC

```json
["yes", "no"]
```

---

## 5. Request Examples

### 5.1 Minimal (required fields only)

```json
{
  "customerName": "Jane Smith",
  "customerEmail": "jane.smith@example.com",
  "customerPhone": "07123456789"
}
```

### 5.2 Full (direct format)

```json
{
  "customerName": "Jane Smith",
  "customerEmail": "jane.smith@example.com",
  "customerPhone": "07123456789",
  "customerFirstName": "Jane",
  "customerLastName": "Smith",
  "address": "123 High Street, London",
  "addressPostcode": "SW1A 1AA",
  "addressLat": 51.5074,
  "addressLng": -0.1278,
  "addressUdprn": "12345678",
  "propertyType": "house",
  "propertyDescription": "detached",
  "bedrooms": 3,
  "bathrooms": 2,
  "floors": 2,
  "floorArea": 120,
  "floorAreaUnit": "sqm",
  "fuelType": "mains_gas",
  "wallType": "cavity_wall",
  "cavityWallInsulation": "insulated",
  "windowType": "double_glazed",
  "roofInsulation": "100mm",
  "projectType": "heat_pump",
  "hasEPC": "no",
  "hearAboutUs": "Partner website",
  "homeEnergy": "gas_boiler",
  "tenure": "owned",
  "externalSpace": "yes",
  "cylinderSpace": "yes",
  "renovating": "no",
  "goals": "reduce_bills"
}
```

### 5.3 Full request body (all fields)

```json
{
  "partnerId": "acme-ltd",
  "customerName": "Jane Smith",
  "customerEmail": "jane.smith@example.com",
  "customerPhone": "07123456789",
  "address": "123 High Street, London",
  "addressPostcode": "SW1A 1AA",
  "addressLat": 51.5074,
  "addressLng": -0.1278,
  "addressUdprn": "12345678",
  "propertyType": "house",
  "propertyDescription": "detached",
  "bedrooms": 3,
  "bathrooms": 2,
  "floors": 2,
  "floorArea": 120,
  "floorAreaUnit": "sqm",
  "fuelType": "mains_gas",
  "wallType": "cavity_wall",
  "cavityWallInsulation": "insulated",
  "externalWallInsulation": null,
  "windowType": "double_glazed",
  "roofInsulation": "100mm",
  "projectType": "heat_pump",
  "hasEPC": "yes",
  "epcData": {
    "lmkKey": "123456789012",
    "postcode": "SW1A 1AA",
    "address": "123 High Street, London",
    "propertyType": "house",
    "builtForm": "detached",
    "floorArea": 120,
    "wallConstruction": "cavity_wall",
    "windowType": "double_glazing",
    "roofInsulation": "100mm",
    "mainFuel": "mains gas"
  },
  "hearAboutUs": "Partner website",
  "homeEnergy": "gas_boiler",
  "tenure": "owned",
  "externalSpace": "yes",
  "cylinderSpace": "yes",
  "renovating": "no",
  "goals": "reduce_bills",
  "questionsForTeam": "When can you start?"
}
```

---

## 6. Response Specification

### 6.1 Success (HTTP 200)

```json
{
  "success": true,
  "partnerId": "string",
  "leadId": "string",
  "spruce": {
    "status": "submitted | pending",
    "uuid": "string | null",
    "url": "string | null",
    "jobReference": "string | null",
    "error": "string | null",
    "retryable": "boolean"
  },
  "estimate": "object | null",
  "warnings": ["string"]
}
```

- `leadId` — Firestore document ID in `leads` collection
- `spruce.status` — `submitted` when Spruce accepted; `pending` when submission failed
- `estimate` — Heat-loss estimate from Spruce; may be `null` if estimate request failed

### 6.2 Error (HTTP 4xx, 5xx)

```json
{
  "success": false,
  "error": "string"
}
```

### 6.3 HTTP Status Codes

```json
{
  "200": "Success",
  "400": "Invalid JSON, missing payload, or validation errors (name/email/phone)",
  "401": "Missing or invalid API key, or key disabled",
  "403": "Partner disabled, or partnerId in body does not match key",
  "404": "Partner not found",
  "405": "Method not allowed (only POST accepted)",
  "429": "Rate limit exceeded (hour or day)",
  "500": "Internal server error"
}
```

---

## 7. Rate Limiting

Limits are configured per partner or per API key. When exceeded, the API returns `429`.

```json
{
  "maxRequestsPerHour": "number (0 = no limit)",
  "maxRequestsPerDay": "number (0 = no limit)"
}
```

---

## 8. Processing Flow

1. Validate HTTP method (POST only)
2. Authenticate via `Authorization` header
3. Load partner config; verify partner exists and is enabled
4. Check rate limits
5. Validate required customer fields
6. Create lead document in Firestore
7. Submit to Spruce Create Job API
8. Calculate estimate via Spruce Estimates API
9. Update lead with Spruce and estimate results
10. Return response
