# Mayar Headless API — Reference

Compiled from <https://docs.mayar.id> on 2026-05-01. This is the subset the
menu-bar app uses (balance + transactions). For everything else, see the
[full docs index](https://docs.mayar.id/llms.txt).

## Base URLs

| Environment | Base URL |
|---|---|
| Production | `https://api.mayar.id` |
| Sandbox    | `https://api.mayar.club` |

All headless endpoints live under `/hl/v1`.

## Authentication

Create an API key at <https://web.mayar.id/api-keys> (production) or the
matching sandbox dashboard at `web.mayar.club`. Each environment has its own
key; rotating your domain/subdomain invalidates the existing key.

Send the key as a bearer token:

```
Authorization: Bearer <YOUR_API_KEY>
```

Never commit the key. Don't share it.

## Endpoints

### GET `/hl/v1/balance` — account balance

No query parameters.

```json
{
  "statusCode": 200,
  "messages": "success",
  "data": {
    "balanceActive": 0,
    "balancePending": 0,
    "balance": 0
  }
}
```

| Field | Meaning |
|---|---|
| `balanceActive`  | Withdrawable funds (IDR, integer) |
| `balancePending` | Held funds, not yet withdrawable |
| `balance`        | Sum of active + pending |

### GET `/hl/v1/transactions` — paid transactions (history)

Query parameters:

| Param | Type | Default |
|---|---|---|
| `page`     | int | 1 |
| `pageSize` | int | 10 |

Response root:

```json
{
  "statusCode": 200,
  "messages": "success",
  "hasMore": true,
  "pageCount": 12,
  "pageSize": 10,
  "page": 1,
  "data": [ /* transactions */ ]
}
```

Each transaction:

| Field | Notes |
|---|---|
| `id` | UUID |
| `credit` | Amount received (IDR, integer) |
| `status` | e.g. `settled` |
| `balanceHistoryType` | `digital_product`, `event`, `membership`, `webinar`, … |
| `paymentMethod` | `QRIS`, e-wallet name, VA bank, `Gratis`, … |
| `customerId` | UUID |
| `createdAt` | epoch milliseconds |
| `fee` | array `[{ xendit_fee, mayar_fee }]` |
| `customer` | `{ name, email, mobile }` |
| `paymentLink` | `{ id, name }` |
| `xenditTransaction` | gateway details (optional) |

### GET `/hl/v1/transactions/unpaid` — unpaid / pending invoices

Same pagination params as above. Response root adds a `total` field.

Each unpaid transaction:

| Field | Notes |
|---|---|
| `id` | UUID |
| `createdAt` | epoch ms |
| `type` | category |
| `amount` | IDR, integer |
| `status` | current state |
| `urlParamTrackingData` | string \| null |
| `paymentLinkId` | UUID |
| `customerId` | UUID |
| `customeField` | object \| null (sic — Mayar's spelling) |
| `customer` | `{ id, email, name, mobile }` |
| `paymentLink` | `{ id, category, name, link, description, … }` |
| `paymentUrl` | gateway URL the customer pays at |

## Related (not used by this app, listed for convenience)

- Webhook history: `GET /hl/v1/webhook/history`
- Register webhook: `POST /hl/v1/webhook/register`
- Test / retry webhook: see <https://docs.mayar.id/api-reference/webhook/>
