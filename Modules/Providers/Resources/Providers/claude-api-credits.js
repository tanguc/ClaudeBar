// The monthly API credit of a Max/Ultra/Team plan, read from the Admin API's
// cost report: the spend since the plan last renewed, against the credit.
// Anthropic reports no credit balance, so what is left is the credit minus
// that spend. Amounts come in cents as decimal strings and never pass
// through a binary float. The cycle starts on the renewal day, in local
// time; buckets are UTC days, so a day either side of the renewal can be
// counted in the wrong cycle.
function read(response, context) {
    var body;
    try { body = jsonDecimal(response.text || ''); } catch (e) { body = null; }
    if (!body || typeof body !== 'object' || !Array.isArray(body.data)) {
        return { error: { parseFailed: "Failed to parse the Claude cost report" } };
    }
    var values = context.values || {};
    var credit = /^[0-9]+(\.[0-9]+)?$/.test(values.monthlyCredit || '') ? values.monthlyCredit : '200';
    var cycle = cycleOf(new Date(context.now * 1000), Number(values.billingDay) || 1);
    var startDay = dayText(cycle.start);

    var cents = '0', items = {};
    body.data.forEach(function (bucket) {
        if (!bucket || typeof bucket.starting_at !== 'string' || bucket.starting_at.slice(0, 10) < startDay) return;
        (Array.isArray(bucket.results) ? bucket.results : []).forEach(function (result) {
            var amount = result ? result.amount : null;
            if (amount === null || amount === undefined || !/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(String(amount))) return;
            var label = lineLabel(result);
            cents = decimalAdd(cents, String(amount));
            items[label] = decimalAdd(items[label] || '0', String(amount));
        });
    });
    var spent = decimalMultiply(cents, '0.01');
    var left = decimalAdd(credit, decimalMultiply(spent, '-1'));
    if (Number(left) < 0) left = '0';
    var lines = Object.keys(items)
        .map(function (label) { return { label: label, used: decimalMultiply(items[label], '0.01') }; })
        .sort(function (a, b) { return Number(b.used) - Number(a.used) || (a.label < b.label ? -1 : 1); });
    var resetsAt = cycle.end.getTime() / 1000;
    return {
        quotas: [{
            type: 'time', name: 'API credits',
            left: { money: left, of: credit, currency: 'USD' },
            resetsAt: resetsAt,
            resetText: 'Spent $' + decimalCents(spent) + ' of $' + decimalCents(credit)
        }],
        cost: { kind: 'apiCost', used: spent, limit: credit, lines: lines, resetsAt: resetsAt, resetText: 'Since ' + startDay }
    };
}

// the renewal day falls on the month's last day in a shorter month
function renewalIn(year, month, day) {
    var last = new Date(year, month + 1, 0).getDate();
    return new Date(year, month, Math.min(day, last));
}

function cycleOf(now, day) {
    var start = renewalIn(now.getFullYear(), now.getMonth(), day);
    if (start > now) start = renewalIn(now.getFullYear(), now.getMonth() - 1, day);
    return { start: start, end: renewalIn(start.getFullYear(), start.getMonth() + 1, day) };
}

function dayText(date) {
    var pad = function (n) { return (n < 10 ? '0' : '') + n; };
    return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate());
}

function lineLabel(result) {
    if (typeof result.model === 'string' && result.model) return result.model;
    var types = { web_search: 'Web search', code_execution: 'Code execution', session_usage: 'Managed Agents sessions', tokens: 'Tokens' };
    if (types[result.cost_type]) return types[result.cost_type];
    return typeof result.description === 'string' && result.description ? result.description : 'Other';
}
