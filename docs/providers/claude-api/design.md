# Claude API credits: design

## Source

`GET https://api.anthropic.com/v1/organizations/analytics/cost` (Usage and Cost Analytics API, beta), headers `x-api-key: <admin key>`, `anthropic-version: 2023-06-01` and `anthropic-beta: analytics-usage-cost-2026-08-24`.

- `starting_at={{system.day-30.iso8601}}`, `ending_at={{system.day+1.iso8601}}`, `time_bucket_width=1d`: a cycle starts at most 30 days before today, and a request spans at most 31 days. `ending_at` is required with a bucket width.
- `group_by[]=product&group_by[]=model`: a row per day, product and model that has cost. Days without cost have no row.
- `cost.amount` is a decimal string in cents with six decimals (`"41280.000000"` is $412.80), after discounts and before credits.

The legacy `cost_report` has no product dimension. A Console organization where Claude Code runs on an API key showed $35.09 of `claude_code` spend there while its Ultra credit stood at $199.99 of $200, so the legacy report can't tell covered spend from the rest.

No endpoint returns the credit balance or the grant. The included credit is spent before purchased credits, so the credit minus the covered spend since renewal is what is left of it, floored at zero.

## Mapping (`claude-api-credits.js`)

- The cycle starts on `billingDay` (default 1) at local midnight; a day past the month's end means its last day. Rows whose `starting_at` date is on or after the start date count.
- One `time` quota, `API credits`: money left of `monthlyCredit` (default 200) after covered spend, resetting at the next renewal. Its text adds the Claude Code spend paid from the balance, when there is any.
- One `apiCost` cost: all spend since renewal, a line per model, with `· Claude Code` on lines the credit doesn't cover. No limit, since part of it is not the credit's.
- Products not covered: `claude_code`. Everything else (Messages API, batch, Managed Agents, Agent SDK, playground) comes off the credit.
- Rows with a null or malformed amount are skipped. A body without a `data` array fails the mapping.

## Limits

- Buckets are UTC days, the cycle is local: a day either side of the renewal can be counted in the wrong cycle.
- `has_more` is not followed: 1000 rows cover 31 days of every product and model in practice.
- The renewal day is a setting: nothing in the API says when the plan renews.

## Sources

- [API credits for Max, Ultra, and Team plans](https://platform.claude.com/docs/en/about-claude/api-credits-for-subscribers)
- [Usage and Cost Analytics API](https://platform.claude.com/docs/en/manage-claude/usage-cost-analytics-api)
- [Usage and Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)
- [Get Cost Report](https://platform.claude.com/docs/en/api/beta/organization/cost_report/retrieve)
