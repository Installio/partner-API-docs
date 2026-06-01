# Technical Specification: Partner Lead Submit API

**Version:** 1.2  
**Endpoint:** `partnerLeadSubmit`  
**Purpose:** Accept lead submissions from partner systems via API key authentication.

**Also see:** [Partner API overview](./PARTNER_API.md) (environments, auth, rate limits, errors, endpoint choice). To update customer contact details on an existing lead, use [Update Lead Customer](./updateLeadCustomer.md).

---

## 1. Overview

The Partner Lead Submit API lets you submit leads from your own systems—CRMs, websites, or internal tools—without embedding the widget. Send customer and property details in a single request and receive a lead ID, heat-loss estimate, and job reference.

The same request can also include an optional `callbackRequest` object. This supports the ECS single-call flow where job creation and callback preferences are submitted together instead of as two separate requests.

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

**Wrapped format** — widget fields nested under `data`; optional `partnerId` and `callbackRequest` at root for validation.

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

### 3.4 Energy Performance Certificate (`hasEPC`, `epcData`)

When the property has a registered EPC, set `hasEPC` to `"yes"` and include an `epcData` object. When no certificate is available, set `hasEPC` to `"no"` and omit `epcData` or send `null`.

| Field     | Type   | Required | Description                                    |
| --------- | ------ | -------- | ---------------------------------------------- |
| `hasEPC`  | string | No       | `"yes"` or `"no"` (see section 4.10).          |
| `epcData` | object | No       | Certificate-derived property data (see below). |

The `epcData` object is stored on the lead as submitted. It supplements root-level property fields (section 3.3) when those are absent and informs Spruce job creation and heat-loss estimates.

#### 3.4.1 Recommended fields

For reliable Spruce integration, include at least:

| Field                  | Type   | Description                                                      |
| ---------------------- | ------ | ---------------------------------------------------------------- |
| `epcCertificateNumber` | string | EPC registry reference (RRN), format `0000-0000-0000-0000-0000`. |
| `postcode`             | string | Postcode on the certificate.                                     |
| `address`              | string | Full address as shown on the certificate.                        |

Accepted aliases for the certificate reference: `certificateNumber`, `lmkKey`, `legacyLmkKey` (32-character legacy identifier).

#### 3.4.2 Field reference

All fields below are optional. Include every field your integration holds; omit keys you do not have.

**Certificate and location**

| Field                  | Type   | Description                                          |
| ---------------------- | ------ | ---------------------------------------------------- |
| `epcCertificateNumber` | string | Primary certificate reference (RRN).                 |
| `certificateNumber`    | string | Alias of `epcCertificateNumber`.                     |
| `lmkKey`               | string | Alias of `epcCertificateNumber` (legacy field name). |
| `legacyLmkKey`         | string | Legacy 32-character certificate key, if applicable.  |
| `address`              | string | Certificate address.                                 |
| `postcode`             | string | Certificate postcode.                                |

**Energy performance**

| Field                       | Type             | Description                                |
| --------------------------- | ---------------- | ------------------------------------------ |
| `energyRating`              | string           | Current efficiency band (e.g. `"C"`).      |
| `energyEfficiency`          | number \| string | Current SAP rating.                        |
| `potentialEnergyRating`     | string           | Potential efficiency band.                 |
| `potentialEnergyEfficiency` | number \| string | Potential SAP rating.                      |
| `lodgementDate`             | string           | Certificate registration date.             |
| `epcYear`                   | number \| string | Year of registration.                      |
| `environmentImpactCurrent`  | number \| string | Environmental impact score.                |
| `co2EmissionsCurrent`       | number \| string | Current CO₂ emissions (tonnes per year).   |
| `co2EmissionsPotential`     | number \| string | Potential CO₂ emissions (tonnes per year). |

**Property type and size**

| Field                    | Type             | Description                                                                |
| ------------------------ | ---------------- | -------------------------------------------------------------------------- |
| `propertyType`           | string           | Normalized type: `house`, `flat`, or `bungalow` (see section 4.1).         |
| `propertyTypeRaw`        | string           | Property type as printed on the certificate.                               |
| `builtForm`              | string           | Normalized built form (e.g. `detached`, `semi_detached`; see section 4.2). |
| `builtFormRaw`           | string           | Built form as printed on the certificate.                                  |
| `floorArea`              | number \| string | Total floor area.                                                          |
| `floorAreaUnit`          | string           | Unit for `floorArea` (e.g. `"square metres"`).                             |
| `numberOfHabitableRooms` | number \| string | Count of habitable rooms.                                                  |

**Building fabric and heating**

| Field                     | Type   | Description                                           |
| ------------------------- | ------ | ----------------------------------------------------- |
| `wallType`                | string | Normalized wall type (see section 4.4).               |
| `wallConstruction`        | string | Wall construction summary.                            |
| `wallsDescription`        | string | Wall description from the certificate.                |
| `windowType`              | string | Normalized glazing type (see section 4.7).            |
| `windowsDescription`      | string | Window description from the certificate.              |
| `glazedType`              | string | Glazing description from the certificate.             |
| `loftInsulation`          | string | Loft insulation level.                                |
| `roofInsulation`          | string | Roof insulation level (see section 4.8).              |
| `roofDescription`         | string | Roof description from the certificate.                |
| `fuelType`                | string | Normalized fuel type (see section 4.3).               |
| `mainFuel`                | string | Main fuel description from the certificate.           |
| `mainHeatDescription`     | string | Main heating system description from the certificate. |
| `constructionAgeBand`     | string | Construction age band (e.g. `"1996-2002"`).           |
| `constructionAgeBandCode` | string | Age-band code.                                        |
| `floorDescription`        | string | Floor description from the certificate.               |
| `floorLevel`              | string | Floor level (relevant for flats).                     |

Numeric values may be sent as numbers or strings; the API coerces known numeric fields to numbers on storage.

#### 3.4.3 Example payloads

**Certificate reference only** (use when root-level property fields in section 3.3 are already complete):

```json
{
  "hasEPC": "yes",
  "epcData": {
    "epcCertificateNumber": "1700-1141-0422-4422-3253",
    "postcode": "SW1A 1AA",
    "address": "123 High Street, London"
  }
}
```

**Certificate with full property detail** (use when EPC is the primary source for heat-loss mapping):

```json
{
  "hasEPC": "yes",
  "epcData": {
    "epcCertificateNumber": "1700-1141-0422-4422-3253",
    "postcode": "SW1A 1AA",
    "address": "123 High Street, London",
    "energyRating": "C",
    "energyEfficiency": 72,
    "potentialEnergyRating": "B",
    "potentialEnergyEfficiency": 85,
    "lodgementDate": "2020-06-15",
    "epcYear": 2020,
    "propertyType": "house",
    "propertyTypeRaw": "House",
    "builtForm": "detached",
    "builtFormRaw": "Detached",
    "floorArea": 120,
    "floorAreaUnit": "square metres",
    "numberOfHabitableRooms": 4,
    "wallType": "cavity_wall",
    "wallConstruction": "cavity_wall",
    "wallsDescription": "Cavity wall, as built, insulated (assumed)",
    "windowType": "double_glazed",
    "windowsDescription": "Fully double glazed",
    "loftInsulation": "100mm",
    "roofInsulation": "100mm",
    "roofDescription": "Pitched, 100 mm loft insulation",
    "fuelType": "mains_gas",
    "mainFuel": "mains gas (not community)",
    "mainHeatDescription": "Boiler and radiators, mains gas",
    "constructionAgeBand": "1996-2002",
    "constructionAgeBandCode": "K",
    "co2EmissionsCurrent": 3.2,
    "environmentImpactCurrent": 52
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
  "callbackRequest": "object (optional; same shape as section 3.7)",
  "data": {
    /* widget fields */
  }
}
```

### 3.7 Optional callback request

Use this when the partner wants to create the lead/job and include callback preferences in the same request.

The recommended location is top-level `callbackRequest`, but wrapped payloads may also send the same object under `data.callbackRequest`. Snake-case aliases are also accepted for interoperability.

For compatibility, the same callback fields can also be sent as flat fields at root level or under `data` (without nesting under `callbackRequest`).

```json
{
  "callbackRequest": {
    "questionsForCall": "string (optional, trimmed, max 8000 chars)",
    "preferredCallTimeSlots": ["string"],
    "preferredCallDays": ["string"]
  }
}
```

Supported aliases inside the callback object:

- `questionsForCall` or `questions_for_call`
- `preferredCallTimeSlots` or `preferred_call_time_slots`
- `preferredCallDays` or `preferred_call_days`

Accepted flat locations (same field names/aliases):

- root level (e.g. `questionsForCall`, `preferredCallDays`)
- `data` level (e.g. `data.questionsForCall`, `data.preferredCallDays`)

Current widget values are:

- `preferredCallTimeSlots`: `9-12`, `12-14`, `14-16`, `16-18`
- `preferredCallDays`: `monday`, `tuesday`, `wednesday`, `thursday`, `friday`

When present, the backend normalizes the object and stores:

- `questionsForCall` as a trimmed string
- `preferredCallTimeSlots` as a trimmed string array (max 32 values)
- `preferredCallDays` as a trimmed string array (max 32 values)
- `submittedAt` as an ISO timestamp

### 3.8 Optional ECS integration metadata (INS-674 alignment)

For ECS middleware, use this in the same `create_job` request that also contains `callbackRequest`.

These fields are optional and are persisted on the lead under `ecs`, then echoed in the success response.

| Semantic field            | Under `ecs`                              | Root-level aliases                            | Type   |
| ------------------------- | ---------------------------------------- | --------------------------------------------- | ------ |
| External identifier       | `externalId` or `external_id`            | `ecsExternalId`, `ecs_external_id`            | string |
| Correlation / trace id    | `correlationId` or `correlation_id`      | `ecsCorrelationId`, `ecs_correlation_id`      | string |
| Installio job reference   | `installioJobRef` or `installio_job_ref` | `ecsInstallioJobRef`, `ecs_installio_job_ref` | string |
| Free-form metadata object | `metadata`                               | `ecsMetadata`                                 | object |

`metadata` must be a JSON object if provided.

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
  "goals": "reduce_bills",
  "callbackRequest": {
    "questionsForCall": "Can you explain the installation timeline?",
    "preferredCallTimeSlots": ["9-12", "14-16"],
    "preferredCallDays": ["monday", "wednesday"]
  }
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
    "epcCertificateNumber": "1700-1141-0422-4422-3253",
    "postcode": "SW1A 1AA",
    "address": "123 High Street, London",
    "energyRating": "C",
    "energyEfficiency": 72,
    "epcYear": 2020,
    "propertyType": "house",
    "propertyTypeRaw": "House",
    "builtForm": "detached",
    "builtFormRaw": "Detached",
    "floorArea": 120,
    "floorAreaUnit": "square metres",
    "numberOfHabitableRooms": 4,
    "wallType": "cavity_wall",
    "wallConstruction": "cavity_wall",
    "wallsDescription": "Cavity wall, as built, insulated (assumed)",
    "windowType": "double_glazed",
    "windowsDescription": "Fully double glazed",
    "loftInsulation": "100mm",
    "roofInsulation": "100mm",
    "mainFuel": "mains gas (not community)",
    "fuelType": "mains_gas",
    "constructionAgeBand": "1996-2002",
    "constructionAgeBandCode": "K",
    "co2EmissionsCurrent": 3.2,
    "environmentImpactCurrent": 52
  },
  "hearAboutUs": "Partner website",
  "homeEnergy": "gas_boiler",
  "tenure": "owned",
  "externalSpace": "yes",
  "cylinderSpace": "yes",
  "renovating": "no",
  "goals": "reduce_bills",
  "questionsForTeam": "When can you start?",
  "callbackRequest": {
    "questionsForCall": "What happens after the survey?",
    "preferredCallTimeSlots": ["12-14"],
    "preferredCallDays": ["tuesday", "thursday"]
  }
}
```

### 5.4 ECS single-call create job + callback (recommended)

```json
{
  "data": {
    "customerName": "Jane Smith",
    "customerEmail": "jane.smith@example.com",
    "customerPhone": "07123456789",
    "address": "123 High Street, London",
    "addressPostcode": "SW1A 1AA",
    "propertyType": "house",
    "propertyDescription": "detached",
    "bedrooms": 3,
    "floorArea": 120,
    "floorAreaUnit": "sqm",
    "fuelType": "mains_gas",
    "wallType": "cavity_wall",
    "cavityWallInsulation": "insulated",
    "windowType": "double_glazed",
    "roofInsulation": "100mm",
    "callbackRequest": {
      "questionsForCall": "Please call after 2pm.",
      "preferredCallTimeSlots": ["14-16"],
      "preferredCallDays": ["tuesday", "thursday"]
    }
  },
  "ecs": {
    "externalId": "ecs-job-001",
    "correlationId": "550e8400-e29b-41d4-a716-446655440000",
    "installioJobRef": "installio-ref-123",
    "metadata": {
      "sourceSystem": "ecs-middleware"
    }
  }
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
  "hubspot": {
    "status": "pending",
    "message": "HubSpot sync runs via Firestore after Spruce completes"
  },
  "ecs": {
    "externalId": "string | null",
    "correlationId": "string | null",
    "installioJobRef": "string | null",
    "metadata": "object | null"
  },
  "callbackRequest": {
    "questionsForCall": "string",
    "preferredCallTimeSlots": ["string"],
    "preferredCallDays": ["string"],
    "submittedAt": "2026-04-01T10:00:00.000Z"
  },
  "estimate": "object | null",
  "estimateSummary": "object | null",
  "lead": "object | null",
  "warnings": ["string"]
}
```

- `leadId` — Firestore document ID in `leads` collection
- `spruce.status` — `submitted` when Spruce accepted the job; `pending` when job creation failed (may be retried server-side; see `retryable`)
- `hubspot` — HubSpot push is asynchronous; status becomes `submitted` on the lead document after the Firestore trigger succeeds
- `ecs` — normalized ECS integration metadata when supplied; otherwise keys are present with `null` values
- `callbackRequest` — normalized callback object when supplied; otherwise `null`. When callback data is supplied, response always includes `questionsForCall`, `preferredCallTimeSlots`, `preferredCallDays`, and `submittedAt`.
- `estimate` — Full JSON from Spruce `POST /v1/estimates` on success, with extra pricing fields on each `estimates[]` row (see below); `null` if the estimate request failed
- `estimateSummary` — Small convenience object derived from the first `estimates[]` row; `null` if `estimate` is `null`
- `lead` — Latest Firestore lead snapshot after create + Spruce/estimate update (full stored document). Returned as `null` only if snapshot read fails.
- `warnings` — e.g. rate-limiter fallback messages when applicable

### 6.2 Example success body (estimate present)

The **`estimate`** object below matches a **real** Spruce `POST /v1/estimates` response shape (as stored on the lead). Spruce may add or rename fields over time—treat undocumented keys as opaque. Grant-inclusive totals in **pence** can be **negative** when subsidies exceed net customer cost (this example shows positive values).

```json
{
  "success": true,
  "partnerId": "acme-ltd",
  "leadId": "abc123firestoreId",
  "spruce": {
    "status": "submitted",
    "uuid": "00000000-0000-4000-8000-000000000000",
    "url": "https://example.spruce.app/jobs/...",
    "jobReference": "SP-12345",
    "error": null,
    "retryable": false
  },
  "hubspot": {
    "status": "pending",
    "message": "HubSpot sync runs via Firestore after Spruce completes"
  },
  "callbackRequest": {
    "questionsForCall": "Can you explain the installation timeline?",
    "preferredCallTimeSlots": ["9-12", "14-16"],
    "preferredCallDays": ["monday", "wednesday"],
    "submittedAt": "2026-04-01T10:00:00.000Z"
  },
  "estimate": {
    "url": "https://api.spruce.eco/estimate/00000000-0000-4000-8000-000000000001",
    "estimates": [
      {
        "annual_heat_energy_demand_w": 11867370,
        "average_heat_pump_efficiency": 3.94,
        "co2_saved_kg": 2455,
        "commutes_saved_petrol_car": 681,
        "efficiency_baseline": 0.87,
        "electricity_tariff_baseline_annual_bill_gbp": 863,
        "electricity_tariff_baseline_pence_per_kwh": 6.33,
        "electricity_tariff_baseline_price_cap_pence_per_kwh": 25.73,
        "electricity_tariff_heat_pump_annual_bill_gbp": 620,
        "electricity_tariff_heat_pump_annual_bill_price_cap_gbp": 774,
        "electricity_tariff_heat_pump_based_on": "Based on Octopus's expectations of customer consumption patterns on the cosy octopus tariff as of July 2025",
        "electricity_tariff_heat_pump_pence_per_kwh": 20.6,
        "flights_to_spain_saved": 12,
        "flow_temp_c": 45,
        "fuel_name_baseline": "Mains Gas",
        "heat_pumps": [
          {
            "calculated_capacity_w": 4550,
            "calculated_scop": 4.13,
            "inventory_heat_pump_name": "Grant HP R290 4"
          }
        ],
        "hot_water_cylinders": [
          {
            "capacity_l": 180,
            "inventory_hot_water_cylinder_name": "UK Elite Cylinder Heat Pump 180L 545(D)x1313(H) - ESHPD3180"
          }
        ],
        "internal_temp_c": 20,
        "outdoor_temp_c": -1.7,
        "overall_scop": 4.13,
        "price_cap_description": "Price cap 1st July - 30th September 2025",
        "total_heat_loss_w": 3336,
        "total_price_excluding_grants_pence": 1226580,
        "total_price_including_grants_pence": 476580,
        "customer_discount_rate_percent": 0.15,
        "discounted_total_price_including_grants_pence": 405093
      }
    ]
  },
  "estimateSummary": {
    "url": "https://api.spruce.eco/estimate/00000000-0000-4000-8000-000000000001",
    "estimateCount": 1,
    "totalHeatLossW": 3336,
    "totalPriceIncludingGrantsPence": 476580,
    "customer_discount_rate_percent": 0.15,
    "discounted_total_price_including_grants_pence": 405093
  },
  "lead": {
    "id": "abc123firestoreId",
    "partnerId": "acme-ltd",
    "status": "new",
    "submissionChannel": "partner_lead_api",
    "property": {
      "address": "123 High Street, London",
      "postcode": "SW1A 1AA",
      "propertyType": "house",
      "bedrooms": 3,
      "floorArea": 120
    },
    "customer": {
      "firstName": "Jane",
      "lastName": "Smith",
      "email": "jane.smith@example.com",
      "phone": "07123456789"
    },
    "hasEPC": "yes",
    "epcData": {
      "epcCertificateNumber": "1700-1141-0422-4422-3253",
      "postcode": "SW1A 1AA",
      "address": "123 High Street, London",
      "energyRating": "C",
      "floorArea": 120,
      "propertyType": "house",
      "builtForm": "detached"
    },
    "qualifyingQuestions": {
      "goals": "reduce_bills"
    },
    "ecs": {
      "externalId": "ecs-job-001",
      "correlationId": "550e8400-e29b-41d4-a716-446655440000",
      "installioJobRef": "installio-ref-123",
      "metadata": {
        "sourceSystem": "ecs-middleware"
      }
    },
    "callbackRequest": {
      "questionsForCall": "Can you explain the installation timeline?",
      "preferredCallTimeSlots": ["9-12", "14-16"],
      "preferredCallDays": ["monday", "wednesday"],
      "submittedAt": "2026-04-01T10:00:00.000Z"
    },
    "spruce": {
      "status": "submitted",
      "uuid": "00000000-0000-4000-8000-000000000000",
      "jobReference": "SP-12345",
      "estimateUrl": "https://api.spruce.eco/estimate/00000000-0000-4000-8000-000000000001"
    },
    "hubspot": {
      "status": "pending"
    },
    "estimate": {},
    "metadata": {
      "userAgent": "string",
      "referer": "string",
      "ip": "string"
    },
    "createdAt": "2026-04-01T10:00:00.000Z",
    "updatedAt": "2026-04-01T10:00:01.000Z"
  },
  "warnings": []
}
```

**`estimate` top-level**

| Field          | Type              | Description                                         |
| -------------- | ----------------- | --------------------------------------------------- |
| `url`          | string \| omitted | Heat-loss report page URL (primary)                 |
| `estimate_url` | string \| omitted | Same role as `url` if Spruce uses this alias        |
| `estimates`    | array             | One object per sizing / scenario returned by Spruce |

**Each `estimate.estimates[]` row — fields observed from Spruce**

Numeric types in the API are often integers or doubles; clients may receive either. **`customer_discount_rate_percent`** and **`discounted_total_price_including_grants_pence`** are **added by this backend** on each row (see [Partner Estimate API — customer discount](./partnerEstimateSubmit.md#51-customer-discount-ecs-heat-pump-pricing)).

| Field                                                    | Type           | Description                                                                                                                                 |
| -------------------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `annual_heat_energy_demand_w`                            | number         | Annual heat energy demand (watt-hours basis per Spruce model)                                                                               |
| `average_heat_pump_efficiency`                           | number         | Average heat pump efficiency (ratio)                                                                                                        |
| `co2_saved_kg`                                           | number         | CO₂ savings vs baseline (kg)                                                                                                                |
| `commutes_saved_petrol_car`                              | number         | Commute-equivalent savings metric                                                                                                           |
| `efficiency_baseline`                                    | number         | Baseline system efficiency (e.g. gas boiler)                                                                                                |
| `electricity_tariff_baseline_annual_bill_gbp`            | number         | Baseline annual electricity bill (£GBP integer in observed payloads)                                                                        |
| `electricity_tariff_baseline_pence_per_kwh`              | number         | Baseline tariff (p/kWh)                                                                                                                     |
| `electricity_tariff_baseline_price_cap_pence_per_kwh`    | number         | Baseline cap reference (p/kWh)                                                                                                              |
| `electricity_tariff_heat_pump_annual_bill_gbp`           | number         | Heat-pump scenario annual bill (£GBP)                                                                                                       |
| `electricity_tariff_heat_pump_annual_bill_price_cap_gbp` | number         | Heat-pump bill under price-cap assumption (£GBP)                                                                                            |
| `electricity_tariff_heat_pump_based_on`                  | string         | Human-readable tariff / methodology note                                                                                                    |
| `electricity_tariff_heat_pump_pence_per_kwh`             | number         | Effective heat-pump tariff (p/kWh)                                                                                                          |
| `flights_to_spain_saved`                                 | number         | Flights-equivalent savings metric                                                                                                           |
| `flow_temp_c`                                            | number         | Design flow temperature (°C)                                                                                                                |
| `fuel_name_baseline`                                     | string         | Baseline fuel label (e.g. `"Mains Gas"`)                                                                                                    |
| `heat_pumps`                                             | array          | Selected heat pump line items; each element may include e.g. `calculated_capacity_w`, `calculated_scop`, `inventory_heat_pump_name`         |
| `hot_water_cylinders`                                    | array          | Cylinder line items; each element may include e.g. `capacity_l`, `inventory_hot_water_cylinder_name`                                        |
| `internal_temp_c`                                        | number         | Internal design temperature (°C)                                                                                                            |
| `outdoor_temp_c`                                         | number         | Outdoor design temperature (°C)                                                                                                             |
| `overall_scop`                                           | number         | Overall SCOP                                                                                                                                |
| `price_cap_description`                                  | string         | Label for the price-cap period used                                                                                                         |
| `total_heat_loss_w`                                      | number         | Total heat loss (W)                                                                                                                         |
| `total_price_excluding_grants_pence`                     | number         | Installation total (**pence**) before grants                                                                                                |
| `total_price_including_grants_pence`                     | number         | Total (**pence**) after grants—can be negative if grants exceed cost                                                                        |
| `customer_discount_rate_percent`                         | number         | **Added by this API:** contractual discount decimal (e.g. `0.15` = 15%)                                                                     |
| `discounted_total_price_including_grants_pence`          | number \| null | **Added by this API:** `total_price_including_grants_pence * (1 - customer_discount_rate_percent)`, rounded; `null` if source price missing |

Spruce may also return **camelCase** equivalents for some quantities (e.g. `totalHeatLossW`, `totalPriceIncludingGrantsPence`); this backend reads those in **`estimateSummary`** when building the summary from the first row.

**`estimateSummary` (when `estimate` succeeds)**

| Field                                           | Type           | Description                                                                              |
| ----------------------------------------------- | -------------- | ---------------------------------------------------------------------------------------- |
| `url`                                           | string \| null | Report URL (from `estimate.url` or `estimate.estimate_url`)                              |
| `estimateCount`                                 | number         | `estimate.estimates.length`                                                              |
| `totalHeatLossW`                                | number \| null | From first row: `total_heat_loss_w` or `totalHeatLossW`                                  |
| `totalPriceIncludingGrantsPence`                | number \| null | From first row: `total_price_including_grants_pence` or `totalPriceIncludingGrantsPence` |
| `customer_discount_rate_percent`                | number         | Discount rate applied (from first row or partner default)                                |
| `discounted_total_price_including_grants_pence` | number \| null | From first row after enrichment                                                          |

When the estimate call fails, **`estimate`** and **`estimateSummary`** are both **`null`**; the HTTP response is still **200** if the lead was created and the response is otherwise successful.

### 6.3 `lead` object fields (stored Firestore snapshot)

`lead` includes all currently stored lead fields. Common top-level keys are:

- `id`, `partnerId`, `widgetVersion`, `status`, `salesStatus`, `submissionChannel`
- `property` (normalized property fields)
- `customer` (name/email/phone)
- `epcData` (full field list in [section 3.4](#34-optional-epc-fields)), `hasEPC`
- `qualifyingQuestions`
- `ecs`
- `callbackRequest`
- `spruce`
- `hubspot`
- `estimate`
- `metadata`
- `createdAt`, `updatedAt`

Exact nested keys can evolve as integrations add fields (for example under `spruce`, `hubspot`, or `estimate`).

### 6.4 Error (HTTP 4xx, 5xx)

```json
{
  "success": false,
  "error": "string"
}
```

### 6.5 HTTP Status Codes

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
6. Normalize optional `callbackRequest` (single-call create job + callback flow)
7. Normalize optional ECS metadata (`ecs` / root aliases)
8. Create lead document in Firestore
9. Submit to Spruce Create Job API
10. Calculate estimate via Spruce Estimates API
11. Update lead with Spruce and estimate results
12. Return response
