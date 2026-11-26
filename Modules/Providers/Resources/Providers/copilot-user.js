function read(response) {
    const json = response.json;
    if (!json || typeof json !== 'object') return {error: {parseFailed: 'Failed to parse Copilot API response'}};
    const plan = typeof json.copilot_plan === 'string' ? json.copilot_plan : null;
    const premium = json.quota_snapshots && json.quota_snapshots.premium_interactions;
    // Unlimited, or no AI-credits quota at all: the plan, and no made-up 100% (the Left law).
    const account = typeof json.login === 'string' && json.login ? {email: json.login} : undefined;
    if (!premium) return {quotas: [], plan, account};
    if (premium.unlimited === true) {
        // An uncapped seat (business, billed per token) still counts what was spent: a note, no bar.
        const used = Number(premium.credits_used);
        if (!Number.isFinite(used) || used <= 0) return {quotas: [], plan, account};
        const reset = resetDay(json.quota_reset_date_utc || json.quota_reset_date);
        const text = String(Math.round(used)).replace(/\B(?=(\d{3})+(?!\d))/g, ',') + ' AI credits used, no cap' + (reset ? ', resets ' + reset : '');
        return {quotas: [], notes: [{group: 'Monthly', label: 'AI credits', text}], plan, account};
    }

    const entitlement = Number(premium.entitlement) || 0;
    const remaining = Number(premium.remaining) || 0;
    const percent = typeof premium.percent_remaining === 'number' ? premium.percent_remaining
        : entitlement > 0 ? remaining / entitlement * 100 : null;
    if (percent == null) return {quotas: [], plan, account};

    const quota = {type: 'time', name: 'Monthly', percentRemaining: Math.max(0, Math.min(100, percent)),
                   resetText: Math.max(0, entitlement - remaining) + '/' + entitlement + ' AI credits'};
    // The month that ends on GitHub's reset date — its real length.
    const reset = Date.parse(json.quota_reset_date_utc || json.quota_reset_date || '');
    if (Number.isFinite(reset)) {
        const end = new Date(reset);
        const start = Date.UTC(end.getUTCFullYear(), end.getUTCMonth() - 1, end.getUTCDate(), end.getUTCHours(), end.getUTCMinutes(), end.getUTCSeconds());
        quota.resetsAt = reset / 1000;
        quota.windowSeconds = (reset - start) / 1000;
    }
    return {quotas: [quota], plan, account};
}

// "2026-12-01" -> "1 Dec", in UTC like GitHub's reset date
function resetDay(text) {
    const at = Date.parse(text || '');
    if (!Number.isFinite(at)) return null;
    const day = new Date(at);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return day.getUTCDate() + ' ' + months[day.getUTCMonth()];
}
