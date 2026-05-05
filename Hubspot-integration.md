# OMS <-> HubSpot API Reference

Professional reference for the lead sync between OMS Firestore leads and HubSpot CRM.

This document covers:

1. OMS -> HubSpot lead push
2. HubSpot -> OMS webhook updates
3. HubSpot APIs used
4. Field-level mapping, types, and update behavior

## Scope

The integration is implemented by these functions:

- `onLeadHubSpotPush`: Firestore trigger that creates and updates HubSpot contacts and deals
- `hubspotWebhook`: public HTTP endpoint that receives HubSpot deal property change webhooks

## High-Level Flow

### OMS -> HubSpot

1. A lead is written to Firestore under `leads/{leadId}`.
2. `onLeadHubSpotPush` waits until `spruce.status` is no longer `pending`.
3. The trigger finds or creates a HubSpot contact by email.
4. The trigger creates a HubSpot deal.
5. The trigger associates the deal to the contact using HubSpot Associations v4.
6. The OMS lead is updated with HubSpot IDs, status, response payloads, and sync metadata.
7. On later lead edits, the same trigger PATCHes the existing HubSpot contact and deal if mapped content changed.

### HubSpot -> OMS

1. HubSpot sends `deal.propertyChange` events to `hubspotWebhook`.
2. The handler verifies the HubSpot signature when `HUBSPOT_WEBHOOK_CLIENT_SECRET` is configured.
3. The handler finds OMS leads where `hubspot.dealId == {hubspot deal id}`.
4. The handler updates mapped Firestore fields from the changed HubSpot property.
5. For `dealstage`, the handler also updates OMS `salesStatus`.

## Runtime Components

| Component | Direction | Type | Purpose |
|---|---|---|---|
| `onLeadHubSpotPush` | OMS -> HubSpot | Firestore trigger | Create deal/contact, keep HubSpot in sync |
| `hubspotWebhook` | HubSpot -> OMS | HTTPS endpoint | Apply HubSpot deal field updates to Firestore |


## HubSpot APIs Used

### Contact APIs

| Method | HubSpot API | Used for |
|---|---|---|
| `GET` | `/crm/v3/objects/contacts/{email}?idProperty=email` | Find contact by email |
| `POST` | `/crm/v3/objects/contacts` | Create contact |
| `PATCH` | `/crm/v3/objects/contacts/{contactId}` | Update contact |

### Deal APIs

| Method | HubSpot API | Used for |
|---|---|---|
| `POST` | `/crm/v3/objects/deals` | Create deal |
| `PATCH` | `/crm/v3/objects/deals/{dealId}` | Update deal |
| `PUT` | `/crm/v4/objects/deals/{dealId}/associations/contacts/{contactId}` | Associate deal to contact |
| `GET` | `/crm/v3/properties/deals` | Debug endpoint: list deal properties |
| `POST` | `/crm/v3/objects/deals/batch/read` | Debug endpoint: read a deal with all properties |

## Authentication

### OMS -> HubSpot

- Auth mechanism: HubSpot Private App token
- Config key: `HUBSPOT_API_KEY`
- Region handling:
  - EU tokens such as `eu1-...` or `pat-eu1-...` use `https://api-eu1.hubapi.com`
  - Otherwise default is `https://api.hubapi.com`
  - `HUBSPOT_REGION=eu|us` can override auto-detection

### HubSpot -> OMS webhook

- Auth mechanism: HubSpot webhook signature validation
- Config key: `HUBSPOT_WEBHOOK_CLIENT_SECRET`
- Supported signature formats:
  - v1
  - v2
  - v3

If `HUBSPOT_WEBHOOK_CLIENT_SECRET` is not set, the webhook endpoint accepts unsigned requests. That is only safe for local development.

## Trigger Rules

### Create behavior

`onLeadHubSpotPush` creates HubSpot records when all of the following are true:

- the lead document exists
- `spruce.status` is not `pending`
- `customer.email` is present
- `hubspot.status` is not already `submitted`
- the lead is not already being processed with `hubspot.status === "pushing"`

### Update behavior

`onLeadHubSpotPush` updates existing HubSpot records when:

- `hubspot.status === "submitted"`
- `hubspot.dealId` exists
- mapped lead content changed

The trigger intentionally ignores write-back-only changes such as:

- `hubspot.lastSyncedAt`
- `metadata.hubspotLastSync`
- `updatedAt`

This prevents sync loops.

### Resume behavior

The trigger performs one automatic resume attempt if:

- a contact and deal were created
- the deal-contact association failed
- `hubspot.associationResumeAttempted` is not yet set

## Contact Field Mapping

These fields are always sent to HubSpot contact records.

| HubSpot contact property | OMS source | Type sent to HubSpot | Create | Update |
|---|---|---|---|---|
| `email` | `customer.email` | string | Yes | Yes |
| `firstname` | `customer.firstName` | string | Yes | Yes |
| `lastname` | `customer.lastName` | string | Yes | Yes |
| `phone` | `customer.phone` | string | Yes | Yes |

Notes:

- Contacts are keyed by email.
- If a contact already exists, the integration PATCHes the latest name and phone values.
- If contact creation returns a duplicate error, the code looks the contact up again by email and PATCHes the latest name and phone (same behavior as when the contact was found on the first lookup).

## Deal Field Strategy

Deal payloads are assembled from three groups:

1. Core deal properties always managed by code
2. Structured portal properties derived from the lead document
3. Optional env-configured custom properties

Only non-empty values are sent.

INS-659 callback preferences on the lead (`callbackRequest`) map to **deal** properties (`preferred_days`, `preferred_times`, `callback_questions`). HubSpot models those as deal fields, not contact fields, even if similarly named properties exist on contacts. See `.env.example` for a short reference comment next to related HubSpot settings.

### Core deal properties

| HubSpot deal property | Source | Type sent to HubSpot | Create | Update |
|---|---|---|---|---|
| `dealname` | `Lead: {address}` else `Lead {omsLeadId}` | string | Yes | Yes |
| `pipeline` | `HUBSPOT_DEAL_PIPELINE` or `default` | string | Yes | No |
| `dealstage` | `HUBSPOT_DEAL_STAGE` | string | Yes if configured | No |

Notes:

- `pipeline` and `dealstage` are only set on create.
- `updateDeal()` intentionally does not overwrite stage or pipeline, so sales users can move deals manually in HubSpot.

## Default Structured Portal Deal Fields

When `HUBSPOT_DEAL_STRUCTURED_PROPERTIES` is enabled and `HUBSPOT_DEAL_STRUCTURED_FIELD_SET=portal` (default), the integration may send the following deal properties.

All values are sent as strings because the HubSpot API request body is built from stringified values.

| HubSpot deal property | OMS source / logic | Type sent to HubSpot | Create | Update |
|---|---|---|---|---|
| `acquisition_or_partner_source` | partner mapping or partner display name | string | Yes | Yes |
| `amount` | total estimate GBP | decimal string | Yes | Yes |
| `bathrooms` | `property.bathrooms` | string | Yes | Yes |
| `bedrooms` | `property.bedrooms` | string | Yes | Yes |
| `built_year_or_band` | `epcData.constructionAgeBand` or similar EPC fields | string | Yes | Yes |
| `bus_grant_eligibility` | derived from grant amount | string | Yes | Yes |
| `callback_questions` | `callbackRequest.questionsForCall` | string (truncated to 4000 chars) | Yes when present | Yes when present |
| `closed_won_reason` | not populated by OMS push | not sent | No | No |
| `closed_lost_reason` | not populated by OMS push | not sent | No | No |
| `commercial_notes` | combined customer name, email, phone | string | Yes | Yes |
| `cost_estimate_total` | total estimate GBP | decimal string | Yes | Yes |
| `cost_heat_pump_parts` | estimate part cost GBP | decimal string | Yes | Yes |
| `cost_installation` | installation cost GBP | decimal string | Yes | Yes |
| `cost_radiators` | radiator cost GBP | decimal string | Yes | Yes |
| `cost_survey` | survey cost GBP | decimal string | Yes | Yes |
| `deal_handling_status` | mapped from OMS `status` | string | Yes when mapped | Yes when mapped |
| `design_temp_c` | `estimate.estimates[0].flow_temp_c` | string | Yes | Yes |
| `discovery_call_date` | not populated by OMS push | not sent | No | No |
| `estimate_bill_savings_year` | derived annual savings | string | Yes | Yes |
| `estimate_co_savings_kgyear` | `estimate.estimates[0].co2_saved_kg` | string | Yes | Yes |
| `estimate_last_opened` | not populated by OMS push | not sent | No | No |
| `estimate_sent_date` | `spruce.submittedAt` | HubSpot date millis string | Yes | Yes |
| `estimate_url` | estimate URL from Spruce/estimate context | string | Yes | Yes |
| `estimate_viewed` | not populated by OMS push | not sent | No | No |
| `floor_area_m` | `property.floorArea` | string | Yes | Yes |
| `floors` | `property.floors` | string | Yes | Yes |
| `flow_temperature_c` | `estimate.estimates[0].flow_temp_c` | string | Yes | Yes |
| `grant_bus` | derived grant amount GBP | decimal string | Yes | Yes |
| `heat_loss_per_m_wm` | derived from total heat loss / floor area | decimal string | Yes | Yes |
| `heat_loss_total_kw` | derived from total heat loss | decimal string | Yes | Yes |
| `homeowner_motivation` | mapped from `qualifyingQuestions.goals` | string | Yes | Yes |
| `internal_temp_c` | `estimate.estimates[0].internal_temp_c` | string | Yes | Yes |
| `interested_in_battery` | derived from `qualifyingQuestions.homeEnergy.battery` | boolean string (`true`/`false`) | Yes | Yes |
| `interested_in_heat_pump` | derived from `qualifyingQuestions.homeEnergy.heat_pump` or estimate presence | boolean string (`true`/`false`) | Yes | Yes |
| `latitude` | `property.lat` | string | Yes | Yes |
| `lead_handing_status` | mapped from OMS `status` | string | Yes when mapped | Yes when mapped |
| `longitude` | `property.lng` | string | Yes | Yes |
| `preferred_days` | `callbackRequest.preferredCallDays` | string (semicolon-separated, title-cased day values) | Yes when present | Yes when present |
| `preferred_times` | `callbackRequest.preferredCallTimeSlots` | string (semicolon-separated; widget slot keys like `9-12` mapped to portal labels such as `9am - 12pm midday`) | Yes when present | Yes when present |
| `project_details` | property description plus qualifying questions JSON | string | Yes | Yes |
| `property_address_line` | `property.address` | string | Yes | Yes |
| `property_postcode` | `property.postcode` | string | Yes | Yes |
| `property_type` | mapped from `property.propertyType` | string | Yes | Yes |
| `proposal_accepted_date` | not populated by OMS push | not sent | No | No |
| `proposal_requested` | not populated by OMS push | not sent | No | No |
| `proposal_sent_date` | not populated by OMS push | not sent | No | No |
| `proposal_sent_date_b2b` | not populated by OMS push | not sent | No | No |
| `proposal_value` | total estimate GBP | decimal string | Yes | Yes |
| `proposal_viewed` | not populated by OMS push | not sent | No | No |
| `qualification_outcome` | mapped from OMS `status` | string | Yes when mapped | Yes when mapped |
| `quoted_amount` | total estimate GBP | decimal string | Yes | Yes |
| `rate_card_requested` | not populated by OMS push | not sent | No | No |
| `rate_card_sent_date` | not populated by OMS push | not sent | No | No |
| `rejection_reason` | not populated by OMS push | not sent | No | No |
| `scop` | `estimate.estimates[0].overall_scop` | string | Yes | Yes |
| `solar_deal_id` | OMS lead ID | string | Yes | Yes |
| `spruce_job_id` | `spruce.uuid` | string | Yes | Yes |
| `spruce_job_name` | `spruce.jobReference` else `spruce.uuid` | string | Yes | Yes |
| `spruce_job_reference` | `spruce.jobReference` | string | Yes | Yes |
| `spruce_lead_source_tag` | `HUBSPOT_DEAL_SPRUCE_LEAD_SOURCE_TAG` or `estimate_widget` | string | Yes | Yes |
| `spruce_project_type` | `property.projectType` | string | Yes | Yes |
| `survey_booked_date` | not populated by OMS push | not sent | No | No |
| `survey_booked_date_and_time` | not populated by OMS push | not sent | No | No |
| `survey_completed_date` | not populated by OMS push | not sent | No | No |
| `survey_requested_date` | not populated by OMS push | not sent | No | No |
| `survey_required` | not populated by OMS push | not sent | No | No |
| `system_design_cylinder` | first hot water cylinder name | string | Yes | Yes |
| `system_design_heat_pump_model` | first heat pump name | string | Yes | Yes |
| `walls` | `property.wallType` | string | Yes | Yes |
| `windows` | `property.windowType` | string | Yes | Yes |

Notes:

- Any property with no value is omitted from the request.
- Numeric and boolean values are stringified before being sent to HubSpot.
- Portal allowlist membership for deal PATCHes is defined in `integrations/hubspotPortalDealPropertyAllowlist.json` (plus optional env extras); the INS-659 callback deal fields are included there when using the portal field set.

## Firestore Fields Used To Detect OMS -> HubSpot Resync

Changes in these lead fields can trigger an outbound HubSpot PATCH after the initial push:

- `customer`
- `property`
- `qualifyingQuestions`
- `callbackRequest`
- `estimate`
- `epcData`
- `hasEPC`
- `partnerId`
- `status`
- `spruce.uuid`
- `spruce.jobReference`
- `spruce.url`
- `spruce.estimateUrl`
- `spruce.status`

## OMS Lead Fields Written By Outbound Sync

After create/update attempts, the OMS lead is updated with:

| Firestore field | Type | Meaning |
|---|---|---|
| `hubspot.status` | string | `pushing`, `submitted`, or `failed` |
| `hubspot.pushedAt` | timestamp | Last create/resume attempt time |
| `hubspot.contactId` | string or null | HubSpot contact ID |
| `hubspot.dealId` | string or null | HubSpot deal ID |
| `hubspot.dealUrl` | string or null | HubSpot CRM deep link when `HUBSPOT_PORTAL_ID` is set |
| `hubspot.response` | object | Raw result metadata from contact/deal operations |
| `hubspot.error` | string or null | Last create/resume error |
| `hubspot.lastSyncedAt` | timestamp | Last update-sync time after PATCH |
| `hubspot.syncError` | string or null | Last PATCH error |
| `hubspot.associationResumeAttempted` | boolean | Prevents repeated resume attempts |
| `metadata.hubspotLastPush` | object | Summary of last create/resume run |
| `metadata.hubspotLastSync` | object | Summary of last update-sync run |

## HubSpot Webhook Contract

### Endpoint

- Function: `hubspotWebhook`
- Type: public HTTP endpoint
- Accepted methods:
  - `GET` and `HEAD`: health/ping, returns `200 ok`
  - `POST`: webhook delivery

### Subscription types

The webhook implementation is built around HubSpot deal subscriptions.

| Event | Subscription type | Current OMS handler behavior |
|---|---|---|
| Created | `deal.creation` | Received only if configured in HubSpot; currently ignored by the handler |
| Deleted | `deal.deletion` | Received only if configured in HubSpot; currently ignored by the handler |
| Deal property changed | `deal.propertyChange` | Processed when `objectId` is present |

Important:

- the current handler only applies `deal.propertyChange`
- `deal.creation` and `deal.deletion` can be subscribed in HubSpot for visibility, but they are not written into Firestore by the current code
- events without `objectId` are skipped

### Property-change subscriptions to configure in HubSpot

For each HubSpot deal field you want OMS to react to, create a HubSpot webhook subscription with:

- subscription type: `deal.propertyChange`
- object type: deal
- property name: one of the internal property names below

### Deal property subscriptions currently processed by OMS

These subscriptions are supported by the current `hubspotWebhook` handler and will update Firestore.

| HubSpot deal property | Subscription type | Sent by OMS backend | OMS action |
|---|---|---|---|
| `dealstage` | `deal.propertyChange` | Yes | Updates `salesStatus` and HubSpot sync metadata |
| `amount` | `deal.propertyChange` | Yes | Updates `hubspot.amount` |
| `bathrooms` | `deal.propertyChange` | Yes | Updates `property.bathrooms` |
| `bedrooms` | `deal.propertyChange` | Yes | Updates `property.bedrooms` |
| `bus_grant_eligibility` | `deal.propertyChange` | Yes | Updates `hubspot.busGrantEligibility` |
| `closed_won_reason` | `deal.propertyChange` | No | Updates `hubspot.closedWonReason` |
| `closed_lost_reason` | `deal.propertyChange` | No | Updates `hubspot.closedLostReason` |
| `closedate` | `deal.propertyChange` | No | Updates `hubspot.closeDate` |
| `commercial_notes` | `deal.propertyChange` | Yes | Updates `hubspot.commercialNotes` |
| `credentials_deck_sent` | `deal.propertyChange` | No | Updates `hubspot.credentialsDeckSent` |
| `deal_handling_status` | `deal.propertyChange` | Yes | Updates `hubspot.dealHandlingStatus` |
| `decision_maker_contact` | `deal.propertyChange` | No | Updates `hubspot.decisionMakerContact` |
| `discovery_call_date` | `deal.propertyChange` | No | Updates `hubspot.discoveryCallDate` |
| `email` | `deal.propertyChange` | No | Updates `customer.email` |
| `estimate_last_opened` | `deal.propertyChange` | No | Updates `hubspot.estimateLastOpened` |
| `estimate_viewed` | `deal.propertyChange` | No | Updates `hubspot.estimateViewed` |
| `firstname` | `deal.propertyChange` | No | Updates `customer.firstName` |
| `floor_area_m` | `deal.propertyChange` | Yes | Updates `property.floorArea` |
| `floors` | `deal.propertyChange` | Yes | Updates `property.floors` |
| `homeowner_motivation` | `deal.propertyChange` | Yes | Updates `hubspot.homeownerMotivation` |
| `hs_next_step` | `deal.propertyChange` | No | Updates `hubspot.nextStep` |
| `hs_priority` | `deal.propertyChange` | No | Updates `hubspot.priority` |
| `hubspot_owner_assigneddate` | `deal.propertyChange` | No | Updates `hubspot.ownerAssignedDate` |
| `hubspot_owner_id` | `deal.propertyChange` | No | Updates `hubspot.ownerId` |
| `intro_call_date` | `deal.propertyChange` | No | Updates `hubspot.introCallDate` |
| `lastname` | `deal.propertyChange` | No | Updates `customer.lastName` |
| `latitude` | `deal.propertyChange` | Yes | Updates `property.lat` |
| `lead_handing_status` | `deal.propertyChange` | Yes | Updates `hubspot.leadHandingStatus` |
| `likelihood_to_close` | `deal.propertyChange` | No | Updates `hubspot.likelihoodToClose` |
| `longitude` | `deal.propertyChange` | Yes | Updates `property.lng` |
| `phone` | `deal.propertyChange` | No | Updates `customer.phone` |
| `proposal_accepted_date` | `deal.propertyChange` | No | Updates `hubspot.proposalAcceptedDate` |
| `proposal_requested` | `deal.propertyChange` | No | Updates `hubspot.proposalRequested` |
| `proposal_sent_date` | `deal.propertyChange` | No | Updates `hubspot.proposalSentDate` |
| `proposal_sent_date_b2b` | `deal.propertyChange` | No | Updates `hubspot.proposalSentDateB2b` |
| `proposal_value` | `deal.propertyChange` | Yes | Updates `hubspot.proposalValue` |
| `proposal_viewed` | `deal.propertyChange` | No | Updates `hubspot.proposalViewed` |
| `property_address_line` | `deal.propertyChange` | Yes | Updates `property.address` |
| `property_postcode` | `deal.propertyChange` | Yes | Updates `property.postcode` |
| `property_type` | `deal.propertyChange` | Yes | Updates `property.propertyType` |
| `qualification_outcome` | `deal.propertyChange` | Yes | Updates `hubspot.qualificationOutcome` |
| `rate_card_requested` | `deal.propertyChange` | No | Updates `hubspot.rateCardRequested` |
| `rate_card_sent_date` | `deal.propertyChange` | No | Updates `hubspot.rateCardSentDate` |
| `rejection_reason` | `deal.propertyChange` | No | Updates `hubspot.rejectionReason` |
| `survey_booked_date` | `deal.propertyChange` | No | Updates `hubspot.surveyBookedDate` |
| `survey_booked_date_and_time` | `deal.propertyChange` | No | Updates `hubspot.surveyBookedDateAndTime` |
| `survey_completed_date` | `deal.propertyChange` | No | Updates `hubspot.surveyCompletedDate` |
| `survey_requested_date` | `deal.propertyChange` | No | Updates `hubspot.surveyRequestedDate` |
| `survey_required` | `deal.propertyChange` | No | Updates `hubspot.surveyRequired` |
| `walls` | `deal.propertyChange` | Yes | Updates `property.wallType` |
| `windows` | `deal.propertyChange` | Yes | Updates `property.windowType` |

### Deal property subscriptions sent by OMS but currently ignored by OMS webhook handler

These fields are created or updated in HubSpot by `onLeadHubSpotPush`, but a webhook change for them is not currently written back into Firestore because they are not in `HUBSPOT_PROP_TO_FIRESTORE`.

| HubSpot deal property | Subscription type | Sent by OMS backend | OMS action if webhook fires |
|---|---|---|---|
| `acquisition_or_partner_source` | `deal.propertyChange` | Yes | Ignored |
| `built_year_or_band` | `deal.propertyChange` | Yes | Ignored |
| `callback_questions` | `deal.propertyChange` | Yes when `callbackRequest` present | Ignored |
| `cost_estimate_total` | `deal.propertyChange` | Yes | Ignored |
| `cost_heat_pump_parts` | `deal.propertyChange` | Yes | Ignored |
| `cost_installation` | `deal.propertyChange` | Yes | Ignored |
| `cost_radiators` | `deal.propertyChange` | Yes | Ignored |
| `cost_survey` | `deal.propertyChange` | Yes | Ignored |
| `dealname` | `deal.propertyChange` | Yes | Ignored |
| `design_temp_c` | `deal.propertyChange` | Yes | Ignored |
| `estimate_bill_savings_year` | `deal.propertyChange` | Yes | Ignored |
| `estimate_co_savings_kgyear` | `deal.propertyChange` | Yes | Ignored |
| `estimate_sent_date` | `deal.propertyChange` | Yes | Ignored |
| `estimate_url` | `deal.propertyChange` | Yes | Ignored |
| `flow_temperature_c` | `deal.propertyChange` | Yes | Ignored |
| `grant_bus` | `deal.propertyChange` | Yes | Ignored |
| `heat_loss_per_m_wm` | `deal.propertyChange` | Yes | Ignored |
| `heat_loss_total_kw` | `deal.propertyChange` | Yes | Ignored |
| `hs_exchange_rate` | `deal.propertyChange` | No | Ignored |
| `internal_temp_c` | `deal.propertyChange` | Yes | Ignored |
| `interested_in_battery` | `deal.propertyChange` | Yes | Ignored |
| `interested_in_heat_pump` | `deal.propertyChange` | Yes | Ignored |
| `pipeline` | `deal.propertyChange` | Yes | Ignored |
| `preferred_days` | `deal.propertyChange` | Yes when `callbackRequest` present | Ignored |
| `preferred_times` | `deal.propertyChange` | Yes when `callbackRequest` present | Ignored |
| `project_details` | `deal.propertyChange` | Yes | Ignored |
| `quoted_amount` | `deal.propertyChange` | Yes | Ignored |
| `scop` | `deal.propertyChange` | Yes | Ignored |
| `solar_deal_id` | `deal.propertyChange` | Yes | Ignored |
| `spruce_job_id` | `deal.propertyChange` | Yes | Ignored |
| `spruce_job_name` | `deal.propertyChange` | Yes | Ignored |
| `spruce_job_reference` | `deal.propertyChange` | Yes | Ignored |
| `spruce_lead_source_tag` | `deal.propertyChange` | Yes | Ignored |
| `spruce_project_type` | `deal.propertyChange` | Yes | Ignored |
| `system_design_cylinder` | `deal.propertyChange` | Yes | Ignored |
| `system_design_heat_pump_model` | `deal.propertyChange` | Yes | Ignored |

Common portal-only subscriptions such as `deal_currency_code` can also be configured in HubSpot, but they are currently ignored unless a Firestore mapping is added in the webhook handler.

### Payload normalization

The handler accepts:

- an array of webhook events
- an object with `events: [...]`
- a single event object

### Webhook value typing

Important: the webhook handler converts incoming HubSpot `propertyValue` values to strings before writing them to Firestore.

That means:

- `bathrooms`, `bedrooms`, `amount`, `latitude`, `longitude`, and similar fields are stored as strings when updated from HubSpot webhook events
- only metadata fields such as timestamps and booleans retain non-string Firestore types

## HubSpot -> OMS Field Mapping

### Special case: `dealstage`

When HubSpot sends `propertyName = dealstage`, the handler updates:

| Firestore field | Type written | Notes |
|---|---|---|
| `salesStatus` | string or null | Mapped label from `HUBSPOT_DEAL_STAGE_TO_SALES_STATUS`, otherwise raw stage ID |
| `hubspot.dealStageId` | string or null | Raw HubSpot stage ID |
| `hubspot.salesStatusMapped` | boolean | `true` when mapping table matched |
| `hubspot.salesStatusSyncedAt` | timestamp | Sync timestamp |
| `hubspot.lastWebhookAt` | timestamp | Last webhook processing time |
| `hubspot.lastWebhookError` | null or string | Cleared on success, set on write error |
| `hubspot.lastWebhookEventId` | number or null | HubSpot event ID |
| `updatedAt` | timestamp | Lead update timestamp |

### Generic mapped HubSpot deal properties

The following HubSpot deal properties are written into Firestore when received via webhook:

| HubSpot property | Firestore field | Type written to Firestore |
|---|---|---|
| `bathrooms` | `property.bathrooms` | string or null |
| `bedrooms` | `property.bedrooms` | string or null |
| `floor_area_m` | `property.floorArea` | string or null |
| `floors` | `property.floors` | string or null |
| `latitude` | `property.lat` | string or null |
| `longitude` | `property.lng` | string or null |
| `property_address_line` | `property.address` | string or null |
| `property_postcode` | `property.postcode` | string or null |
| `property_type` | `property.propertyType` | string or null |
| `walls` | `property.wallType` | string or null |
| `windows` | `property.windowType` | string or null |
| `firstname` | `customer.firstName` | string or null |
| `lastname` | `customer.lastName` | string or null |
| `email` | `customer.email` | string or null |
| `phone` | `customer.phone` | string or null |
| `lead_handing_status` | `hubspot.leadHandingStatus` | string or null |
| `deal_handling_status` | `hubspot.dealHandlingStatus` | string or null |
| `qualification_outcome` | `hubspot.qualificationOutcome` | string or null |
| `likelihood_to_close` | `hubspot.likelihoodToClose` | string or null |
| `rejection_reason` | `hubspot.rejectionReason` | string or null |
| `closed_lost_reason` | `hubspot.closedLostReason` | string or null |
| `closed_won_reason` | `hubspot.closedWonReason` | string or null |
| `budget_range` | `hubspot.budgetRange` | string or null |
| `homeowner_motivation` | `hubspot.homeownerMotivation` | string or null |
| `hubspot_owner_id` | `hubspot.ownerId` | string or null |
| `hubspot_owner_assigneddate` | `hubspot.ownerAssignedDate` | string or null |
| `amount` | `hubspot.amount` | string or null |
| `closedate` | `hubspot.closeDate` | string or null |
| `proposal_value` | `hubspot.proposalValue` | string or null |
| `survey_required` | `hubspot.surveyRequired` | string or null |
| `survey_requested_date` | `hubspot.surveyRequestedDate` | string or null |
| `survey_booked_date` | `hubspot.surveyBookedDate` | string or null |
| `survey_booked_date_and_time` | `hubspot.surveyBookedDateAndTime` | string or null |
| `survey_completed_date` | `hubspot.surveyCompletedDate` | string or null |
| `proposal_requested` | `hubspot.proposalRequested` | string or null |
| `proposal_sent_date` | `hubspot.proposalSentDate` | string or null |
| `proposal_sent_date_b2b` | `hubspot.proposalSentDateB2b` | string or null |
| `proposal_accepted_date` | `hubspot.proposalAcceptedDate` | string or null |
| `proposal_viewed` | `hubspot.proposalViewed` | string or null |
| `rate_card_requested` | `hubspot.rateCardRequested` | string or null |
| `rate_card_sent_date` | `hubspot.rateCardSentDate` | string or null |
| `credentials_deck_sent` | `hubspot.credentialsDeckSent` | string or null |
| `hs_next_step` | `hubspot.nextStep` | string or null |
| `hs_priority` | `hubspot.priority` | string or null |
| `discovery_call_date` | `hubspot.discoveryCallDate` | string or null |
| `intro_call_date` | `hubspot.introCallDate` | string or null |
| `decision_maker_contact` | `hubspot.decisionMakerContact` | string or null |
| `commercial_notes` | `hubspot.commercialNotes` | string or null |
| `estimate_last_opened` | `hubspot.estimateLastOpened` | string or null |
| `estimate_viewed` | `hubspot.estimateViewed` | string or null |
| `bus_grant_eligibility` | `hubspot.busGrantEligibility` | string or null |
