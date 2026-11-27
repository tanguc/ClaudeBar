// NanoGPT from the steps' answers (`usage`, `balance`): the subscription's
// weekly and daily input-token quotas, its daily images, and the cash balance
// that pays for models outside the subscription.
// https://docs.nano-gpt.com/api-reference/endpoint/subscription-usage.md
// Quotas count input tokens, not dollars. percentUsed is a fraction that can
// pass 1; resetAt is epoch milliseconds. A null counter is unknown, not full.

var WEEK = 604800;
var DAY = 86400;

function read(response) {
    var answers;
    try { answers = JSON.parse(response.text || ''); } catch (e) { answers = null; }
    var usage = answers && answers.usage;
    if (!usage || typeof usage !== 'object' || Array.isArray(usage)) {
        return { error: { parseFailed: "Failed to parse NanoGPT's subscription usage" } };
    }

    var quotas = [];
    var limits = usage.limits || {};
    var note = routing(usage);
    if (usage.active === false || usage.state === 'inactive') {
        quotas.push({ type: 'model', name: 'Subscription', percentRemaining: 0, resetText: 'No active subscription' });
    } else {
        push(quotas, usage.weeklyInputTokens, limits.weeklyInputTokens, 'weekly', null, WEEK, 'input tokens', note);
        push(quotas, usage.dailyInputTokens, limits.dailyInputTokens, 'model', 'Daily tokens', DAY, 'input tokens', null);
        push(quotas, usage.dailyImages, limits.dailyImages, 'model', 'Images', DAY, 'images', null);
    }

    var money = balance(answers.balance);
    if (money) quotas.push(money);
    return quotas.length ? { quotas: quotas } : { error: { parseFailed: 'NanoGPT reported no quota' } };
}

function push(quotas, counter, limit, type, name, windowSeconds, unit, note) {
    if (counter === null || counter === undefined || typeof counter !== 'object') return;
    var used = counter.percentUsed;
    var quota = { type: type, windowSeconds: windowSeconds };
    if (name) quota.name = name;
    if (typeof used === 'number' && isFinite(used)) {
        quota.percentRemaining = Math.max(0, Math.min(100, 100 - used * 100));
    } else {
        // degraded lookup: the counter is unknown, never shown as a full allowance
        quota.percentRemaining = 0;
        quota.resetText = 'Usage unknown right now';
        quotas.push(quota);
        return;
    }
    if (typeof counter.resetAt === 'number' && isFinite(counter.resetAt)) quota.resetsAt = counter.resetAt / 1000;
    var parts = [];
    if (typeof counter.used === 'number' && typeof limit === 'number') parts.push(short(counter.used) + ' of ' + short(limit) + ' ' + unit);
    if (note) parts.push(note);
    if (parts.length) quota.resetText = parts.join(' · ');
    quotas.push(quota);
}

// once the subscription is used up, requests spend the balance (or fail)
function routing(usage) {
    var mode = usage.routing && usage.routing.recommendedMode;
    if (mode === 'paygo') return 'Subscription used up: requests now spend the balance';
    if (mode === 'unavailable') return 'Subscription used up: requests are refused';
    return null;
}

function balance(body) {
    if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
    var spendable = decimal(body.usd_spendable_balance);
    var total = decimal(body.usd_balance);
    var left = spendable !== null ? spendable : total;
    if (left === null) return null;
    var quota = { type: 'model', name: 'Balance', left: { money: left, currency: 'USD' } };
    var pending = decimal(body.usd_pending_usage);
    if (pending !== null && Number(pending) > 0) quota.resetText = 'Pending: $' + Number(pending).toFixed(2);
    return quota;
}

function decimal(value) {
    if (typeof value === 'number' && isFinite(value)) return String(value);
    if (typeof value === 'string' && /^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$/.test(value)) return value;
    return null;
}

function short(n) {
    if (n >= 1e9) return trim(n / 1e9) + 'B';
    if (n >= 1e6) return trim(n / 1e6) + 'M';
    if (n >= 1e3) return trim(n / 1e3) + 'K';
    return String(Math.round(n));
}

function trim(x) {
    return (Math.round(x * 10) / 10).toString();
}
