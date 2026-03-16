# ERP Integration — Salesforce to ERPNext

End-to-end integration between Salesforce CRM and ERPNext 
using MuleSoft as the integration middleware.

## Architecture
Salesforce → MuleSoft → ERPNext

## Features
- Real-time Platform Event subscription (CometD)
- OAuth 2.0 Client Credentials authentication
- Idempotency — no duplicate orders
- Auto retry with 3 attempts (2s delay)
- Exact ERP error reporting in Salesforce
- Full audit trail via Integration Log object

## Tech Stack
| Layer | Technology |
|---|---|
| CRM | Salesforce (Apex, Platform Events) |
| Integration | MuleSoft Anypoint Studio 4.11.0 |
| ERP | ERPNext (Frappe Cloud) |

## Project Structure
- /mulesoft — MuleSoft Anypoint project
- /salesforce — Salesforce metadata (SFDX)
- /docs — Technical documentation

## Setup
See docs/ for full technical documentation.

## Author
Prakashraj Kodimunja
