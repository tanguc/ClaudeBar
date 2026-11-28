// The monthly API credit of a Max/Ultra/Team plan, read from the Usage and
// Cost Analytics API: daily rows by product and model since the plan last
// renewed. Anthropic reports no credit balance, so what is left is the
// credit minus the spend on products it covers. Claude Code is not covered:
// its spend is paid from the purchased balance, so it shows in the cost
// but never comes off the credit. Amounts come in cents as decimal strings
// and never pass through a binary float. The cycle starts on the renewal
// day, in local time; rows are UTC days, so a day either side of the
// renewal can be counted in the wrong cycle.
var NOT_COVERED = { claude_code: 'Claude Code' };

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

    var covered = '0', other = '0', items = {};
    body.data.forEach(function (row) {
        if (!row || typeof row.starting_at !== 'string' || row.starting_at.slice(0, 10) < startDay) return;
        var amount = row.cost ? row.cost.amount : null;
        if (amount === null || amount === undefined || !/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(String(amount))) return;
        var group = row.group || {};
        var outside = NOT_COVERED[group.product];
        if (outside) other = decimalAdd(other, String(amount));
        else covered = decimalAdd(covered, String(amount));
        var label = (typeof group.model === 'string' && group.model ? group.model : 'Other') + (outside ? ' · ' + outside : '');
        items[label] = decimalAdd(items[label] || '0', String(amount));
    });
    var coveredUSD = decimalMultiply(covered, '0.01');
    var totalUSD = decimalMultiply(decimalAdd(covered, other), '0.01');
    var left = decimalAdd(credit, decimalMultiply(coveredUSD, '-1'));
    if (Number(left) < 0) left = '0';
    var lines = Object.keys(items)
        .map(function (label) { return { label: label, used: decimalMultiply(items[label], '0.01') }; })
        .sort(function (a, b) { return Number(b.used) - Number(a.used) || (a.label < b.label ? -1 : 1); });
    var resetsAt = cycle.end.getTime() / 1000;
    var text = 'Covered spend $' + decimalCents(coveredUSD) + ' of $' + decimalCents(credit);
    if (Number(other) > 0) text += ' · Claude Code $' + decimalCents(decimalMultiply(other, '0.01')) + ' from balance';
    return {
        quotas: [{
            type: 'time', name: 'API credits',
            left: { money: left, of: credit, currency: 'USD' },
            resetsAt: resetsAt,
            resetText: text
        }],
        cost: { kind: 'apiCost', used: totalUSD, lines: lines, resetsAt: resetsAt, resetText: 'Since ' + startDay }
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
