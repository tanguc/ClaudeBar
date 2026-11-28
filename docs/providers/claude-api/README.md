---
description: Track the monthly Claude API credit included with a Max, Ultra or Team plan, as spend since the plan renewed against the credit, with an Admin API key. Use when setting up Claude API credits or when it asks for an Admin key.
---

# Claude API credits

Max, Ultra and Team plans include a monthly credit for the Claude API ($100 on Max, $200 on Ultra, up to $500 pooled on Team), paid into the Claude Console organization linked to the plan. This card shows how much of it is left: the organization's spend since the plan last renewed on the products the credit covers, taken off the credit. The cost under it shows every product's spend, with a line per model.

Anthropic has no endpoint for the credit balance, so what is left is worked out from the spend. Purchased credits are spent after the included ones, so the figure holds until the included credit runs out.

**Claude Code isn't covered.** Claude Code requests made with an API key from the linked organization are paid from the purchased balance, not the credit. The card marks those lines `· Claude Code` and keeps them off the credit.

## Setup

1. Claim the credit if you haven't: on claude.ai, **Settings → Billing → API credits**, link a Console organization.
2. In the [Claude Console](https://platform.claude.com/settings/admin-keys), create an **Admin API key** (`sk-ant-admin...`). Admins of the organization can. An individual Console account sets up an organization first, under **Settings → Organization**. Ordinary API keys can't read spend.
3. Settings → Providers → Claude API credits: turn it on. It's **off by default**.
4. Paste the Admin key into **ADMIN API KEY**, or set `ANTHROPIC_ADMIN_KEY` in ClaudeBar's environment.
5. Set **PLAN RENEWAL DAY** to the day of the month your plan renews (the Console's **Billing → Promotional credits** shows the expiry date), and **MONTHLY CREDIT** if yours isn't $200.

## Multiple accounts

**Add Account** takes another organization's Admin key, with that plan's own renewal day and monthly credit; each added account uses only its own key and values. The default account keeps the ones set on the provider. A blank renewal day means the 1st, a blank credit $200.

The `ANTHROPIC_ADMIN_KEY` environment variable comes before a pasted key for every account, so leave it unset when you track several organizations.

## Gotchas

- **"Use an Admin API key (sk-ant-admin...); a normal API key can't read spend."** Anthropic answered 401 or 403: the key isn't an Admin key, or was revoked.
- **The cycle is counted in whole UTC days** from the renewal day, so spend on the day of a renewal can land in the wrong cycle. Credits arrive shortly after the plan payment, not at midnight.
- **Spend shows up within a few minutes** of a request.
- **Claude Code on a subscription isn't here.** The credit doesn't cover Claude Code; the Claude card shows plan limits.

## See also

[troubleshooting](../../troubleshooting.md) · [design](design.md)
