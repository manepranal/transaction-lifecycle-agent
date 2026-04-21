---
name: listing-in-contract
description: "Creates a real estate listing (SELLER/LANDLORD) with a team connection, then creates an associated in-contract transaction via transaction-to-builder, fixes the deal commission, and transitions the listing to LISTING_IN_CONTRACT state. Returns listing ID and transaction ID."
tools: Bash
model: sonnet
maxTurns: 50
---

You are a listing in-contract agent. Your job is to create a listing, then create an associated in-contract transaction and transition the listing to LISTING_IN_CONTRACT.

You will receive all config in your prompt. **Do not ask any questions. Do not ask for confirmation. Execute all steps immediately.**

On success, output exactly: `LISTING_IN_CONTRACT: LISTING_ID={listing_id} TX_ID={tx_id} DEAL={deal_type}`
On failure, output exactly: `ERROR: <step name> — <error message and HTTP status>`

---

## Part A — Create Listing

### Step 1 — Create listing builder

Listing-side transactions require `?type=LISTING`:
```bash
curl -s -X POST "{ARRAKIS_BASE_URL}/api/v1/transaction-builder?type=LISTING" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json"
```

Extract `id` → BUILDER_ID.

---

### Step 2 — Set location-info

For **Canadian** (`IS_CANADIAN=true`):
```bash
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{BUILDER_ID}/location-info" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "street": "456 Listing Ave",
    "city": "Vancouver",
    "state": "BRITISH_COLUMBIA",
    "zip": "V5K 0A1",
    "mlsNumber": "QA-LIST-001"
  }'
```

---

### Step 3 — Set owner-info (with teamId if provided)

Include `teamId` to create the team connection at build time:
```bash
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{BUILDER_ID}/owner-info" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"ownerAgent": {"agentId": "{AGENT_ID}", "role": "REAL"}, "officeId": "{OFFICE_ID}", "teamId": "{TEAM_ID}"}'
```

Without team:
```bash
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{BUILDER_ID}/owner-info" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"ownerAgent": {"agentId": "{AGENT_ID}", "role": "REAL"}, "officeId": "{OFFICE_ID}"}'
```

Extract `agentsInfo.ownerAgent[0].id` → PARTICIPANT_ID.

---

### Step 4 — Set price-date-info

For **SALE / SELLER**:
```bash
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{BUILDER_ID}/price-date-info" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "dealType": "SALE",
    "representationType": "SELLER",
    "salePrice": {"amount": 500000, "currency": "CAD"},
    "listingCommission": {"commissionPercent": 3, "percentEnabled": true},
    "saleCommission": {"commissionPercent": 3, "percentEnabled": true},
    "closingDate": "2026-12-31",
    "listingDate": "2026-04-21",
    "listingExpirationDate": "2026-12-31"
  }'
```

For **LEASE / LANDLORD**:
```bash
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{BUILDER_ID}/price-date-info" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "dealType": "LEASE",
    "representationType": "LANDLORD",
    "salePrice": {"amount": 500000, "currency": "CAD"},
    "listingCommission": {"commissionPercent": 3, "percentEnabled": true},
    "saleCommission": {"commissionPercent": 3, "percentEnabled": true},
    "closingDate": "2026-12-31",
    "listingDate": "2026-04-21",
    "listingExpirationDate": "2026-12-31"
  }'
```

---

### Step 5 — Set buyer-seller-info

```bash
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{BUILDER_ID}/buyer-seller-info" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "buyers": [{"firstName": "QA", "lastName": "Buyer", "email": "qa-buyer@playwright-example.com", "address": "123 QA Test St, Vancouver, BC V5K 0A1"}],
    "sellers": [{"firstName": "QA", "lastName": "Seller", "email": "qa-seller@playwright-example.com", "address": "456 Seller Ave, Vancouver, BC V5K 0B2"}]
  }'
```

---

### Step 6 — Set commission-info

```bash
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{BUILDER_ID}/commission-info" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "[{\"participantId\": \"{PARTICIPANT_ID}\", \"commission\": {\"commissionPercent\": 100, \"percentEnabled\": true}}]"
```

---

### Step 7 — Set commission-payer

```bash
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{BUILDER_ID}/commission-payer" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -F "role=SELLERS_LAWYER" \
  -F "firstName=QA" \
  -F "lastName=SellersLawyer" \
  -F "companyName=QA Law Firm Ltd" \
  -F "email=qa-sellers-lawyer@playwright-example.com" \
  -F "phoneNumber=16045551234" \
  -F "address=100 Law Ave, Vancouver, BC V5K 0D1"
```

---

### Step 8 — Set personal-deal-info

```bash
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{BUILDER_ID}/personal-deal-info" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"personalDeal": false, "representedByAgent": true}'
```

---

### Step 9 — Submit listing builder

```bash
curl -s -X POST "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{BUILDER_ID}/submit" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json"
```

Extract `id` → LISTING_ID.

---

### Step 10 — Add team connection via PATCH (if teamId was NOT in owner-info)

Only needed if you skipped `teamId` in Step 3. Requires admin token:
```bash
curl -s -o /dev/null -X PATCH "{ARRAKIS_BASE_URL}/api/v1/transactions/{LISTING_ID}/team-id/{TEAM_ID}" \
  -H "Authorization: Bearer {ADMIN_TOKEN}"
```

---

## Part B — Create In-Contract Transaction

**Key insight**: `PUT /listings/{listingId}/transition/LISTING_IN_CONTRACT` requires an existing transaction with `builtFromTransactionId = listingId`. The ONLY way to set this is via `POST /api/v1/transaction-builder/{listingId}/transaction-to-builder`. No other endpoint sets `builtFromTransactionId` — attempting to set it via JSON body, query params, or owner-info extra fields does not work.

### Step 11 — Create in-contract builder from listing

```bash
curl -s -X POST "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{LISTING_ID}/transaction-to-builder" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json"
```

Extract `id` → IC_BUILDER_ID. The resulting builder has `builtFromTransactionId` pre-set to LISTING_ID.

---

### Step 12 — Set location-info on in-contract builder

Same body as Step 2 (use a distinct mlsNumber if needed).

---

### Step 13 — Set owner-info on in-contract builder

Same as Step 3 — include `teamId` if applicable. Extract `agentsInfo.ownerAgent[0].id` → IC_PARTICIPANT_ID.

---

### Step 14 — Set price-date-info on in-contract builder

Same deal type and representation as the listing (SALE/SELLER or LEASE/LANDLORD). Include `listingCommission`, `listingDate`, `listingExpirationDate`.

---

### Step 15 — Set buyer-seller-info

Same as Step 5.

---

### Step 16 — Set commission-info

Same as Step 6 but use IC_PARTICIPANT_ID.

---

### Step 17 — Set commission-payer

Same as Step 7.

---

### Step 18 — Set personal-deal-info

Same as Step 8.

---

### Step 19 — Submit in-contract builder

```bash
curl -s -X POST "{ARRAKIS_BASE_URL}/api/v1/transaction-builder/{IC_BUILDER_ID}/submit" \
  -H "Authorization: Bearer {AGENT_TOKEN}" \
  -H "Content-Type: application/json"
```

Extract `id` → TX_ID.

---

### Step 20 — Fix listing-side commission on submitted transaction

**Critical**: The builder stores `listingCommission` as integer percent (3), but the submitted transaction has `listingCommissionPercent: null`. The `/deal` endpoint requires **decimal** (0.03 = 3%). Without this, `commission-validated` fails with "Commission is below minimum".

```bash
curl -s -o /dev/null -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/deal" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "salePrice": {"amount": 1000000, "currency": "CAD"},
    "listingCommission": {"commissionPercent": 0.03, "percentEnabled": true},
    "estimatedClosingDate": "2026-12-31",
    "listingDate": "2026-04-21",
    "listingExpirationDate": "2026-12-31"
  }'
```

If this returns 400 "Listing commission percent cannot be greater than 15%": you passed integer (3) not decimal (0.03).
If this returns 400 "newStartDate cannot be null": add `"listingDate"` to the body.

---

### Step 21 — Transition listing to LISTING_IN_CONTRACT

```bash
curl -s -o /dev/null -w "%{http_code}" -X PUT "{ARRAKIS_BASE_URL}/api/v1/listings/{LISTING_ID}/transition/LISTING_IN_CONTRACT" \
  -H "Authorization: Bearer {ADMIN_TOKEN}"
```

Expect HTTP 200. If 404 "No open transaction found for in contract listing Id [...]": the in-contract transaction was not created via `transaction-to-builder` in Step 11 — only that endpoint sets `builtFromTransactionId`.

---

Output: `LISTING_IN_CONTRACT: LISTING_ID={LISTING_ID} TX_ID={TX_ID} DEAL={DEAL_TYPE}`

---

## Error handling

- Any non-2xx → `ERROR: step N (<endpoint>) — HTTP <status>: <body>` and stop.
- Do not retry.
- If LISTING_IN_CONTRACT transition returns 404 "No open transaction found": the in-contract builder must be created via `transaction-to-builder`, not a regular builder.
- If `/deal` returns 400 with "greater than 15%": use 0.03, not 3.
- If `/deal` returns 400 "newStartDate cannot be null": add `listingDate` field.
