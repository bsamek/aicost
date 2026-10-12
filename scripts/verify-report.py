#!/usr/bin/env python3
"""Independent read-only accounting check against the app's --report JSON."""
import argparse
import collections
import datetime as dt
from decimal import Decimal
import json
from pathlib import Path
import sys
from zoneinfo import ZoneInfo

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('report')
parser.add_argument('codex_home', nargs='?')
parser.add_argument('claude_home', nargs='?')
parser.add_argument('--pi-home')
args = parser.parse_args()
report = json.loads(Path(args.report).read_text())
now = dt.datetime.fromisoformat(report['asOf'].replace('Z', '+00:00'))
tz = ZoneInfo('America/New_York')
now_local = now.astimezone(tz)
pricing = json.loads(Path('Sources/CostCore/Resources/pricing.json').read_text())
home = Path(args.codex_home).expanduser() if args.codex_home else Path.home() / '.codex'
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
# Claude's counters are request totals, not cumulative Codex snapshots.
claude_home = Path(args.claude_home).expanduser() if args.claude_home else Path.home() / '.claude'
messages = {}
for path in sorted((claude_home / 'projects').rglob('*.jsonl')):
    for line in path.open():
        try:
            record = json.loads(line)
            message = record.get('message', {})
            if record.get('type') != 'assistant' or not isinstance(message, dict) or 'usage' not in message: continue
            identity = message['id']; usage = message['usage']; model = message['model']
            stamp = dt.datetime.fromisoformat(record['timestamp'].replace('Z', '+00:00'))
            counts = [usage[k] for k in ('input_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens', 'output_tokens')]
            if not identity or any(type(n) is not int or n < 0 for n in counts) or sum(counts[:3]) > 2**63-1: continue
        except (ValueError, KeyError, TypeError): continue
        request_id = record.get('requestId')
        if identity in messages:
            previous = messages[identity]
            if usage != previous['usage'] or model != previous['model'] or (request_id and previous['request_id'] and request_id != previous['request_id']):
                previous['conflict'] = True
            previous['stamp'] = min(stamp, previous['stamp'])
            previous['request_id'] = previous['request_id'] or request_id
        else:
            messages[identity] = dict(usage=usage, model=model, stamp=stamp, request_id=request_id, conflict=False)
for message in messages.values():
    stamp = message['stamp']; local = stamp.astimezone(tz)
    if stamp > now or (local.year, local.month) != (now_local.year, now_local.month): continue
    usage = message['usage']; model = message['model']; rates = pricing['models'].get(model)
    issue = message['conflict'] or not rates
    rate = (rates or {}).get('short', {})
    context = sum(usage[k] for k in ('input_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens'))
    if rates and rates.get('long') and context > rates.get('longContextThreshold', pricing['longContextThreshold']): rate = rates['long']
    split = usage.get('cache_creation')
    five = (split or {}).get('ephemeral_5m_input_tokens', 0)
    hour = (split or {}).get('ephemeral_1h_input_tokens', 0)
    if split is None and usage['cache_creation_input_tokens']: issue = True
    if split is not None and (any(type(n) is not int or n < 0 for n in (five, hour)) or five + hour != usage['cache_creation_input_tokens']): issue = True
    if (usage['cache_read_input_tokens'] and not rate.get('cached')) or (five and not rate.get('writes5m')) or (hour and not rate.get('writes1h')): issue = True
    cost = Decimal(0) if issue else sum((Decimal(usage['input_tokens']) * Decimal(rate['input']),
        Decimal(usage['cache_read_input_tokens']) * Decimal(rate.get('cached', '0')),
        Decimal(five) * Decimal(rate.get('writes5m', '0')), Decimal(hour) * Decimal(rate.get('writes1h', '0')),
        Decimal(usage['output_tokens']) * Decimal(rate['output'])), Decimal(0)) / 1_000_000
    for period in ['month'] + (['today'] if local.date() == now_local.date() else []):
        row = expected[period][model]; row[0] += cost; row[1] += int(issue)
# Pi usage is per-request, with cache categories disjoint from uncached input.
pi_home = Path(args.pi_home).expanduser() if args.pi_home else Path.home() / '.pi' / 'agent'
pi_pricing = json.loads(Path('Sources/CostCore/Resources/pi-pricing.json').read_text())
pi_messages = {}
for path in sorted((pi_home / 'sessions').rglob('*.jsonl')):
    supported = False
    for line in path.open():
        try:
            record = json.loads(line)
            if record.get('type') == 'session':
                supported = record.get('version') in (2, 3) and bool(record.get('id'))
                continue
            if not supported: continue
            entry = record['id']; entry_type = record.get('type')
            if entry_type == 'message':
                message = record.get('message', {})
                if message.get('role') != 'assistant' or 'usage' not in message: continue
                provider = message['provider']; model = message.get('responseModel') or message['model']
                usage = message['usage']; milliseconds = message['timestamp']
                if not provider or not model or type(milliseconds) is not int or not 0 <= milliseconds <= 253402300799999: continue
                stamp = dt.datetime.fromtimestamp(milliseconds / 1000, dt.timezone.utc)
                response = message.get('responseId')
                identity = (provider, 'response', response) if response else (provider, 'entry', 'message', entry, milliseconds)
            elif entry_type in ('usage', 'compaction', 'branch_summary') and 'usage' in record:
                usage = record['usage']
                stamp = dt.datetime.fromisoformat(record['timestamp'].replace('Z', '+00:00'))
                provider = record.get('provider') or None if entry_type == 'usage' else None
                model = record.get('model') or None if entry_type == 'usage' else None
                response = record.get('responseId') if entry_type == 'usage' and provider else None
                identity = (provider, 'response', response) if response else (provider or 'unattributed', 'entry', entry_type, entry, stamp.timestamp())
            else: continue
            unattributed = not provider or not model
            counts = [usage[k] for k in ('input', 'cacheRead', 'cacheWrite', 'output')]
            hour = usage.get('cacheWrite1h'); reasoning = usage.get('reasoning')
            if not entry: continue
            if any(type(n) is not int or not 0 <= n <= 2**63-1 for n in counts) or sum(counts[:3]) > 2**63-1: continue
            if hour is not None and (type(hour) is not int or not 0 <= hour <= usage['cacheWrite']): continue
            if reasoning is not None and (type(reasoning) is not int or not 0 <= reasoning <= usage['output']): continue
        except (ValueError, KeyError, TypeError, OverflowError): continue
        # cost/totalTokens are derived fields and must not affect duplicate identity.
        normalized = tuple(counts) + (hour, reasoning)
        if identity in pi_messages:
            previous = pi_messages[identity]
            previous['conflict'] |= previous['counts'] != normalized or previous['model'] != model
            previous['stamp'] = min(previous['stamp'], stamp)
        else:
            pi_messages[identity] = dict(provider=provider, model=model, usage=usage, counts=normalized, stamp=stamp, conflict=False, unattributed=unattributed)
for message in pi_messages.values():
    stamp = message['stamp']; local = stamp.astimezone(tz)
    if stamp > now or (local.year, local.month) != (now_local.year, now_local.month): continue
    provider = message['provider']; model = message['model']; usage = message['usage']
    rates = None
    if provider == 'anthropic' and model and model.startswith('claude-'): rates = pricing['models'].get(model)
    elif provider in ('openai', 'openai-codex') and model and not model.startswith('claude-'): rates = pricing['models'].get(model)
    elif provider == 'fireworks' and model: rates = pi_pricing['models'].get(provider + '/' + model)
    issue = message['conflict'] or message['unattributed'] or not rates
    rate = (rates or {}).get('short', {})
    context = usage['input'] + usage['cacheRead'] + usage['cacheWrite']
    if rates and rates.get('long') and context > rates.get('longContextThreshold', pricing['longContextThreshold']): rate = rates['long']
    if usage['cacheRead'] and rate.get('cached') is None: issue = True
    write_cost = Decimal(0)
    if provider == 'anthropic' and usage['cacheWrite']:
        hour = usage.get('cacheWrite1h')
        if hour is None: issue = True
        else:
            five = usage['cacheWrite'] - hour
            if (five and rate.get('writes5m') is None) or (hour and rate.get('writes1h') is None): issue = True
            write_cost = Decimal(five) * Decimal(rate.get('writes5m') or '0') + Decimal(hour) * Decimal(rate.get('writes1h') or '0')
    elif usage['cacheWrite']:
        if rate.get('writes') is None: issue = True
        write_cost = Decimal(usage['cacheWrite']) * Decimal(rate.get('writes') or '0')
    cost = Decimal(0) if issue else (Decimal(usage['input']) * Decimal(rate['input']) + Decimal(usage['cacheRead']) * Decimal(rate.get('cached') or '0') + write_cost + Decimal(usage['output']) * Decimal(rate['output'])) / 1_000_000
    for period in ['month'] + (['today'] if local.date() == now_local.date() else []):
        label = provider + '/' + (model or 'Unknown model') if provider else model or 'Unknown model'
        row = expected[period][label]; row[0] += cost; row[1] += int(issue)
for period in ('today', 'month'):
    observed = {row['model']: (Decimal(row['total']), row['unpriced']) for row in report[period]['models']}
    wanted = {k: tuple(v) for k,v in expected[period].items()}
    assert {k: v[0] for k, v in observed.items()} == {k: v[0] for k, v in wanted.items()}, (period, observed, wanted)
    total = sum((v[0] for v in wanted.values()), Decimal(0))
    assert Decimal(report[period]['total']) == total
    print(f'{period}: ${total} — dollar totals match independent calculation')
