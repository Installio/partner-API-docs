#!/usr/bin/env bash
# Manual curl cases for partnerLeadSubmit — solar (INS-953) + heat smoke.
#
# Usage:
#   export PARTNER_API_KEY='your-dev-partner-key'
#   ./curl-partnerLeadSubmit-solar-tests.sh            # run all
#   ./curl-partnerLeadSubmit-solar-tests.sh solar_with_url
#   ./curl-partnerLeadSubmit-solar-tests.sh solar_minimal
#   ./curl-partnerLeadSubmit-solar-tests.sh solar_create_opensolar
#   ./curl-partnerLeadSubmit-solar-tests.sh missing_lead_type
#   ./curl-partnerLeadSubmit-solar-tests.sh missing_address
#   ./curl-partnerLeadSubmit-solar-tests.sh heat_smoke
#
# Env:
#   PARTNER_API_KEY  (required)
#   BASE_URL         (optional; default = sandbox/dev)

set -euo pipefail

BASE_URL="${BASE_URL:-https://europe-west2-co-pilot-dev-f762b.cloudfunctions.net/partnerLeadSubmit}"
# Prod (do not use unless intentional):
# BASE_URL='https://europe-west2-co-pilot-b7f8e.cloudfunctions.net/partnerLeadSubmit'

if [[ -z "${PARTNER_API_KEY:-}" ]]; then
  echo "Set PARTNER_API_KEY first, e.g.:"
  echo "  export PARTNER_API_KEY='…'"
  exit 1
fi

TS="$(date +%s)"
EXT_ID="curl-solar-${TS}"
CORR_ID="00000000-0000-4000-8000-${TS: -12}"

post() {
  local name="$1"
  local body="$2"
  echo
  echo "════════════════════════════════════════════════════════"
  echo "CASE: ${name}"
  echo "════════════════════════════════════════════════════════"
  curl -sS -w "\nHTTP %{http_code}\n" -X POST "$BASE_URL" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${PARTNER_API_KEY}" \
    -d "$body"
  echo
}

# ── 1) Happy path: solar + partner OpenSolar URL (no OpenSolar create) ──
solar_with_url() {
  post "solar_with_url (expect 200, spruce skipped, openSolar linked)" "{
    \"leadType\": \"solar\",
    \"first_name\": \"Jane\",
    \"last_name\": \"Smith\",
    \"email\": \"jane.smith+${TS}@example.com\",
    \"phone\": \"07123456789\",
    \"address\": \"123 High Street, London\",
    \"tenure\": \"owned\",
    \"property_type\": \"detached\",
    \"annual_electrical_spend\": \"1,276.25\",
    \"annual_electrical_spend_unit\": \"gbp\",
    \"panel_count\": 12,
    \"tariff\": {
      \"name\": \"Octopus Outgoing\",
      \"export_pence_per_kwh\": 15,
      \"import_pence_per_kwh\": 28.5,
      \"standing_charge_cents_per_day\": 48.2
    },
    \"open_solar_url\": \"https://app.opensolar.com/#/projects/12345\",
    \"partner_job_reference\": \"ECS-SOLAR-${TS}\",
    \"ecs\": {
      \"externalId\": \"${EXT_ID}-with-url\",
      \"correlationId\": \"${CORR_ID}\"
    }
  }"
}

# ── 2) Minimal solar (only mandatory fields) ──
solar_minimal() {
  post "solar_minimal (expect 200)" "{
    \"leadType\": \"solar\",
    \"customerFirstName\": \"Alex\",
    \"customerLastName\": \"Tester\",
    \"customerEmail\": \"alex.tester+${TS}@example.com\",
    \"address\": \"10 Downing Street, London\",
    \"ecs\": {
      \"externalId\": \"${EXT_ID}-minimal\",
      \"correlationId\": \"${CORR_ID}\"
    }
  }"
}

# ── 3) Solar without URL + geo → may create OpenSolar project ──
solar_create_opensolar() {
  post "solar_create_opensolar (expect 200; openSolar submitted|skipped|failed)" "{
    \"leadType\": \"solar\",
    \"first_name\": \"Sam\",
    \"last_name\": \"Solar\",
    \"email\": \"sam.solar+${TS}@example.com\",
    \"phone\": \"07911112222\",
    \"address\": \"221B Baker Street, London\",
    \"postcode\": \"NW1 6XE\",
    \"addressLat\": 51.5237,
    \"addressLng\": -0.1585,
    \"tenure\": \"owned\",
    \"property_type\": \"terrace\",
    \"panel_count\": 8,
    \"annual_electrical_spend\": 980,
    \"annual_electrical_spend_unit\": \"gbp\",
    \"partner_job_reference\": \"ECS-OS-CREATE-${TS}\",
    \"ecs\": {
      \"externalId\": \"${EXT_ID}-os-create\",
      \"correlationId\": \"${CORR_ID}\"
    }
  }"
}

# ── 4) Alias: projectType=pv instead of leadType ──
solar_project_type_alias() {
  post "solar_project_type_alias (projectType=pv → solar)" "{
    \"projectType\": \"pv\",
    \"first_name\": \"Pat\",
    \"last_name\": \"Alias\",
    \"email\": \"pat.alias+${TS}@example.com\",
    \"address\": \"1 Test Lane, Manchester\",
    \"ecs\": {
      \"externalId\": \"${EXT_ID}-pv-alias\",
      \"correlationId\": \"${CORR_ID}\"
    }
  }"
}

# ── 5) Negative: missing leadType → 400 ──
missing_lead_type() {
  post "missing_lead_type (expect 400)" "{
    \"first_name\": \"No\",
    \"last_name\": \"Type\",
    \"email\": \"no.type+${TS}@example.com\",
    \"address\": \"1 Nowhere Road\"
  }"
}

# ── 6) Negative: solar missing address → 400 ──
missing_address() {
  post "missing_address (expect 400)" "{
    \"leadType\": \"solar\",
    \"first_name\": \"No\",
    \"last_name\": \"Address\",
    \"email\": \"no.address+${TS}@example.com\"
  }"
}

# ── 7) Negative: invalid leadType → 400 ──
invalid_lead_type() {
  post "invalid_lead_type (expect 400)" "{
    \"leadType\": \"battery\",
    \"first_name\": \"Bad\",
    \"last_name\": \"Type\",
    \"email\": \"bad.type+${TS}@example.com\",
    \"address\": \"1 Nowhere Road\"
  }"
}

# ── 8) Idempotent replay (same ecs.externalId twice) ──
solar_idempotent() {
  local body="{
    \"leadType\": \"solar\",
    \"first_name\": \"Idem\",
    \"last_name\": \"Potent\",
    \"email\": \"idem.potent+${TS}@example.com\",
    \"address\": \"5 Replay Street, Bristol\",
    \"open_solar_url\": \"https://app.opensolar.com/#/projects/99999\",
    \"ecs\": {
      \"externalId\": \"${EXT_ID}-idem\",
      \"correlationId\": \"${CORR_ID}\"
    }
  }"
  post "solar_idempotent #1 (create)" "$body"
  post "solar_idempotent #2 (expect same lead / duplicate returned)" "$body"
}

# ── 9) Heat smoke (regression — needs Spruce-ready address/postcode) ──
heat_smoke() {
  post "heat_smoke (expect 200, spruce + estimate)" "{
    \"leadType\": \"heat\",
    \"customerName\": \"Jane Smith\",
    \"customerEmail\": \"jane.heat+${TS}@example.com\",
    \"customerPhone\": \"07123456789\",
    \"customerFirstName\": \"Jane\",
    \"customerLastName\": \"Smith\",
    \"address\": \"123 High Street, London\",
    \"addressPostcode\": \"SW1A 1AA\",
    \"addressLat\": 51.5074,
    \"addressLng\": -0.1278,
    \"propertyType\": \"house\",
    \"propertyDescription\": \"detached\",
    \"bedrooms\": 3,
    \"bathrooms\": 2,
    \"floors\": 2,
    \"floorArea\": 120,
    \"floorAreaUnit\": \"sqm\",
    \"fuelType\": \"mains_gas\",
    \"wallType\": \"cavity_wall\",
    \"cavityWallInsulation\": \"insulated\",
    \"windowType\": \"double_glazed\",
    \"roofInsulation\": \"100mm\",
    \"projectType\": \"heat_pump\",
    \"hasEPC\": \"no\",
    \"tenure\": \"owned\",
    \"ecs\": {
      \"externalId\": \"${EXT_ID}-heat\",
      \"correlationId\": \"${CORR_ID}\"
    }
  }"
}

run_all() {
  solar_with_url
  solar_minimal
  solar_create_opensolar
  solar_project_type_alias
  missing_lead_type
  missing_address
  invalid_lead_type
  solar_idempotent
  # heat_smoke  # uncomment when you want Spruce regression in the same run
}

case "${1:-all}" in
  all) run_all ;;
  solar_with_url) solar_with_url ;;
  solar_minimal) solar_minimal ;;
  solar_create_opensolar) solar_create_opensolar ;;
  solar_project_type_alias) solar_project_type_alias ;;
  missing_lead_type) missing_lead_type ;;
  missing_address) missing_address ;;
  invalid_lead_type) invalid_lead_type ;;
  solar_idempotent) solar_idempotent ;;
  heat_smoke) heat_smoke ;;
  *)
    echo "Unknown case: $1"
    echo "Cases: all | solar_with_url | solar_minimal | solar_create_opensolar |"
    echo "       solar_project_type_alias | missing_lead_type | missing_address |"
    echo "       invalid_lead_type | solar_idempotent | heat_smoke"
    exit 1
    ;;
esac
