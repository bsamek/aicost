#!/usr/bin/env python3
"""Independent read-only accounting check against the app's --report JSON."""
import collections
import datetime as dt
from decimal import Decimal
import json
from pathlib import Path
import sys
from zoneinfo import ZoneInfo

report = json.loads(Path(sys.argv[1]).read_text())
now = dt.datetime.fromisoformat(report['asOf'].replace('Z', '+00:00'))
tz = ZoneInfo('America/New_York')
now_local = now.astimezone(tz)
pricing = json.loads(Path('Sources/CostCore/Resources/pricing.json').read_text())
home = Path(sys.argv[2]).expanduser() if len(sys.argv) > 2 else Path.home() / '.codex'
fields = ('input_tokens', 'cached_input_tokens', 'cache_write_input_tokens', 'output_tokens', 'reasoning_output_tokens')
sessions = []
for root in ('sessions', 'archived_sessions'):
    for path in (home / root).rglob('*.jsonl'):
        model = None; previous = (0,) * 5; events = []; meta = {}; saw = False
        for line in path.open():
            if not any(word in line for word in ('"session_meta"', '"turn_context"', '"token_count"')):
                continue
            try: record = json.loads(line)
            except ValueError: continue
            payload = record.get('payload') or {}
            if record.get('type') == 'session_meta' and not meta: meta = payload
            elif record.get('type') == 'turn_context': model = payload.get('model')
            elif payload.get('type') == 'token_count' and payload.get('info'):
                info = payload['info']
                counts = info.get('total_token_usage')
                if not counts: continue
                total = tuple(counts.get(k, 0) for k in fields)
                if any(n < 0 for n in total) or total[1] > total[0] or total[4] > total[3]: continue
                try: stamp = dt.datetime.fromisoformat(record['timestamp'].replace('Z', '+00:00'))
                except (KeyError, ValueError): continue
                delta = total if total[0] < previous[0] or total[3] < previous[3] else tuple(a-b for a,b in zip(total, previous))
                last_dict = info.get('last_token_usage')
                last = tuple(last_dict.get(k, 0) for k in fields) if last_dict else None
                issue = False
                if not saw and meta.get('forked_from_id'):
                    created = dt.datetime.fromisoformat(meta.get('timestamp', '0001-01-01T00:00:00Z').replace('Z', '+00:00'))
                    issue = stamp >= created and last != total
                previous = total; saw = True
                if any(n < 0 for n in delta) or delta[1] > delta[0] or delta[4] > delta[3]: continue
                if not any((delta[0], delta[2], delta[3])): continue
                events.append((stamp, total, model, delta, last[0] if last == delta else None, issue))
        sessions.append((meta, events, path.name))
parents = {m.get('id', m.get('session_id', p)): m.get('forked_from_id') or (m.get('history_base') or {}).get('thread_id') for m, _, p in sessions}
def root_of(s):
    seen = {s}
    while parents.get(s) and parents[s] not in seen:
        s = parents[s]; seen.add(s)
    return s
seen = set()
expected = {'today': collections.defaultdict(lambda: [Decimal(0), 0]), 'month': collections.defaultdict(lambda: [Decimal(0), 0])}
sessions.sort(key=lambda row: (row[0].get('timestamp', ''), row[0].get('id', row[2])))
for meta, events, filename in sessions:
    root = root_of(meta.get('id', meta.get('session_id', filename)))
    for stamp, total, model, counts, request_input, issue in events:
        key = (root, stamp, total)
        if key in seen: continue
        seen.add(key)
        if stamp > now: continue
        local = stamp.astimezone(tz)
        if (local.year, local.month) != (now_local.year, now_local.month): continue
        rates = pricing['models'].get(model)
        if not rates: issue = True
        rate = (rates or {}).get('short', {})
        if rates and rates.get('long'):
            if request_input is None and counts[0] > pricing['longContextThreshold']: issue = True
            elif request_input is not None and request_input > pricing['longContextThreshold']: rate = rates['long']
        if counts[2] or (counts[1] and not rate.get('cached')): issue = True
        cost = Decimal(0) if issue else ((counts[0]-counts[1])*Decimal(rate['input']) + counts[1]*Decimal(rate.get('cached') or '0') + counts[3]*Decimal(rate['output']))/1_000_000
        periods = ['month'] + (['today'] if local.date() == now_local.date() else [])
        for period in periods:
            row = expected[period][model or 'Unknown model']; row[0] += cost; row[1] += int(issue)
for period in ('today', 'month'):
    observed = {row['model']: (Decimal(row['total']), row['unpriced']) for row in report[period]['models']}
    wanted = {k: tuple(v) for k,v in expected[period].items()}
    assert {k: v[0] for k, v in observed.items()} == {k: v[0] for k, v in wanted.items()}, (period, observed, wanted)
    total = sum((v[0] for v in wanted.values()), Decimal(0))
    assert Decimal(report[period]['total']) == total
    print(f'{period}: ${total} — dollar totals match independent calculation')
