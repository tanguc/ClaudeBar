# Claude API credits: design

## Source

`GET https://api.anthropic.com/v1/organizations/cost_report` (Admin API, legacy Usage and Cost API, still supported), headers `x-api-key: <admin key>` and `anthropic-version: 2023-06-01`.

- `starting_at={{system.day-30.iso8601}}`, `bucket_width=1d`, `limit=31`: a cycle starts at most 30 days before today, so 31 daily buckets (30 days and today) cover it in one page. `limit` is capped at 31.
- `group_by[]=description` adds `model` and `cost_type` to each result, for the lines.
- `amount` is a decimal string in cents (`"123.45"` is $1.23).

No endpoint returns the credit balance or the grant. The included credit is spent before purchased credits, so the credit minus the spend since renewal is what is left of it, floored at zero.

## Mapping (`claude-api-credits.js`)

- The cycle starts on `billingDay` (default 1) at local midnight; a day past the month's end means its last day. Buckets whose `starting_at` date is on or after the start date count.
- One `time` quota, `API credits`: money left of `monthlyCredit` (default 200), resetting at the next renewal.
- One `apiCost` cost with `limit` = the credit, a line per model, or per cost type for non-token costs (web search, code execution, Managed Agents sessions).
- Results with a null or malformed amount are skipped. A body without a `data` array fails the mapping.

## Limits

- Buckets are UTC days, the cycle is local: a day either side of the renewal can be counted in the wrong cycle.
- Priority Tier costs aren't in the cost report.
- The renewal day is a setting: nothing in the API says when the plan renews.

## Sources

- [API credits for Max, Ultra, and Team plans](https://platform.claude.com/docs/en/about-claude/api-credits-for-subscribers)
- [Usage and Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)
- [Get Cost Report](https://platform.claude.com/docs/en/api/beta/organization/cost_report/retrieve)
