---
name: transaction-closer
description: "Advances one arrakis transaction from NEW/SUBMITTED state all the way to PAYMENT_ACCEPTED. Handles both US (standard) and Canadian (CDA generation + recalculate trick) flows. Returns PAYMENT_ACCEPTED on success."
tools: Bash
model: sonnet
maxTurns: 40
---

You are a transaction closer agent. Your only job is to advance ONE transaction to PAYMENT_ACCEPTED via the arrakis REST API.

You will receive all config in your prompt. **Do not ask any questions. Do not ask for confirmation. Execute all steps immediately.**

On success, output exactly: `PAYMENT_ACCEPTED: {TX_ID}`
On failure, output exactly: `ERROR: <step name> — <error message and HTTP status>`

---

## US Flow (IS_CANADIAN=false)

### Step 1 — Set Compliant
```bash
curl -s -w "\n%{http_code}" -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/set-compliant" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json"
```

### Step 2 — Commission Validated
```bash
curl -s -w "\n%{http_code}" -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/commission-validated" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json"
```

### Step 3 — CD Approved
```bash
curl -s -w "\n%{http_code}" -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/cd-approved" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json"
```

### Step 4 — Approved for Closing
```bash
curl -s -w "\n%{http_code}" -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/approved-for-closing" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"transactionClosedOn\": \"$(date +%Y-%m-%d)\"}"
```

### Step 5 — Get approved commission amount

```bash
curl -s -X GET "{ARRAKIS_BASE_URL}/api/v1/cdas/{TX_ID}/get-approved-commission-document-by-transaction-id" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ep = d.get('expectedPaymentToReal', {})
print(ep.get('amount', 3150), ep.get('currency', 'USD'))
"
```

Extract COMMISSION_AMOUNT and CURRENCY.

### Step 6 — Confirm Commission Deposit
```bash
curl -s -w "\n%{http_code}" -X POST "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/confirmed-commission-deposit" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"amount\": {\"amount\": {COMMISSION_AMOUNT}, \"currency\": \"{CURRENCY}\"}, \"dateReceived\": \"$(date +%Y-%m-%d)\"}"
```

### Step 7 — Closed
```bash
curl -s -w "\n%{http_code}" -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/closed" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json"
```

### Step 8 — Payment Accepted
```bash
curl -s -w "\n%{http_code}" -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/payment-accepted" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json"
```

---

## Canadian Flow (IS_CANADIAN=true)

Canadian transactions require CDA generation before the CD steps work. Run these steps in order:

### Step 1 — Set Compliant
Same as US Step 1.

### Step 1a — (SELLER/LANDLORD only) Fix listing-side commission

For `SELLER` or `LANDLORD` representation transactions, the builder stores `listingCommission` using integer percent (3 = 3%), but the submitted transaction has `listingCommissionPercent: null`. Without this fix, `commission-validated` fails with "Commission is below minimum".

```bash
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/deal" \
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

Then recalculate:
```bash
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/recalculate" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json"
```

**Critical**: `/deal` uses **decimal percent** (0.03 = 3%). Using integer 3 returns "Listing commission percent cannot be greater than 15% of the sale price: 300.00%". Also requires `listingDate` or you get "newStartDate cannot be null".

### Step 2 — Update participant details

Before commission-validated, add BUYERS_LAWYER and update existing lawyers with required fields.

**Add BUYERS_LAWYER** (POST as new participant — required for Canadian transactions):
```bash
curl -s -o /dev/null -X POST "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/participant" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "participantRole": "BUYERS_LAWYER",
    "payer": false,
    "commissionDocumentRecipient": false,
    "passThrough": false,
    "personalDeal": false,
    "firstName": "QA",
    "lastName": "BuyersLawyer",
    "emailAddress": "qa-buyers-lawyer@playwright-example.com",
    "phoneNumber": "16045551234",
    "address": "200 Legal Blvd, Vancouver, BC V5K 0E2",
    "paidViaBusinessEntity": {"name": "QA Buyers Law Inc", "nationalIds": []}
  }'
```

**Find and update SELLERS_LAWYER** (must include company via `paidViaBusinessEntity.name`):
```bash
TX=$(curl -s -X GET "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}" -H "Authorization: Bearer {ADMIN_TOKEN}")
SL_ID=$(echo "$TX" | python3 -c "import json,sys; ps=json.load(sys.stdin).get('otherParticipants',[]); [print(p['id']) for p in ps if p.get('role')=='SELLERS_LAWYER']" 2>/dev/null | head -1)
```

```bash
curl -s -o /dev/null -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/participant/{SL_ID}" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "QA",
    "lastName": "SellersLawyer",
    "emailAddress": "qa-sellers-lawyer@playwright-example.com",
    "address": "100 Law Ave, Vancouver, BC V5K 0D1",
    "paidViaBusinessEntity": {"name": "QA Law Firm Ltd", "nationalIds": []}
  }'
```

### Step 3 — Commission Validated
Same as US Step 2.

### Step 4 — Generate CDA (if state is READY_FOR_COMMISSION_DOCUMENT_GENERATION)

Check state first:
```bash
curl -s -X GET "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('transactionStatus'))"
```

If state is `READY_FOR_COMMISSION_DOCUMENT_GENERATION`:

```bash
# Generate CDA
CDA_RESPONSE=$(curl -s -X POST "{ARRAKIS_BASE_URL}/api/v1/cdas/{TX_ID}/generate-for-transaction-id" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json")
CDA_ID=$(echo "$CDA_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id'))")

# Trigger PDF generation (approves the CDA)
curl -s -X POST "{ARRAKIS_BASE_URL}/api/v1/cdas/$CDA_ID/generate-cda-pdf" \
  -H "Authorization: Bearer {ADMIN_TOKEN}"

# Recalculate — resets state to NEEDS_COMMISSION_VALIDATION
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/recalculate" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json"

# Re-run set-compliant then commission-validated
# With CDA already approved, commission-validated jumps state to COMMISSION_DOCUMENT_SENT
curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/set-compliant" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json"

curl -s -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/commission-validated" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json"
```

### Step 5 — CD Approved
Same as US Step 3.

### Step 5a — Set Compliant again (required before approved-for-closing)

After `cd-approved`, compliance resets. Must call `set-compliant` again:
```bash
curl -s -w "\n%{http_code}" -X PUT "{ARRAKIS_BASE_URL}/api/v1/transactions/{TX_ID}/set-compliant" \
  -H "Authorization: Bearer {ADMIN_TOKEN}" \
  -H "Content-Type: application/json"
```

### Step 6 — Approved for Closing
Same as US Step 4.

### Step 7 — Get approved commission amount (use CAD)
Same as US Step 5 — but CURRENCY will be CAD.

### Step 8 — Confirm Commission Deposit (CAD)
Same as US Step 6 with CAD currency.

### Step 9 — Closed
Same as US Step 7.

### Step 10 — Payment Accepted
Same as US Step 8.

---

## Error handling

- Any 401 → output `ERROR: step N — admin token is invalid (401)` and stop immediately.
- Any other non-2xx → output `ERROR: step N (<endpoint>) — HTTP <status>: <body>` and stop.
- Do not retry failed calls.
- If commission amount cannot be fetched, use a fallback: `3150` for CAD, `3000` for USD.
