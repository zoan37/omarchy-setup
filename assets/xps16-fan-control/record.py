#!/usr/bin/env python3
"""Read-only fan/thermal recorder. No sysfs writes, fan control, or root required."""

import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import platform
import time


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return None


def discover():
    sensors = {}
    # Use DDV for Dell readings; avoid repeatedly invoking the SMM interface.
    for hw in sorted(Path('/sys/class/hwmon').glob('*')):
        name = read(hw / 'name')
        if not name or name == 'dell_smm':
            continue
        for attr in sorted(hw.glob('*_input')):
            if not attr.name.startswith(('temp', 'fan')):
                continue
            stem = attr.name.removesuffix('_input')
            key = f'{name}/{hw.name}/{stem}'
            sensors[key] = {
                'path': str(attr), 'driver': name,
                'label': read(hw / f'{stem}_label') or stem,
                'unit': 'C' if stem.startswith('temp') else 'RPM',
            }
    for zone in sorted(Path('/sys/class/thermal').glob('thermal_zone*')):
        sensors[f'thermal/{zone.name}'] = {
            'path': str(zone / 'temp'), 'driver': 'thermal',
            'label': read(zone / 'type') or zone.name, 'unit': 'C',
        }
    return sensors


def cpu_ticks():
    values = list(map(int, Path('/proc/stat').read_text().splitlines()[0].split()[1:9]))
    # guest and guest_nice are already included in user and nice; omit them.
    return sum(values), values[3] + values[4]


def snapshot(sensors):
    values, errors = {}, {}
    for key, info in sensors.items():
        try:
            value = int(Path(info['path']).read_text())
            if info['unit'] == 'C':
                value /= 1000
                if not -20 <= value <= 127:
                    raise ValueError('temperature outside recording bounds')
            elif value < 0:
                raise ValueError('negative RPM')
            values[key] = value
        except (OSError, ValueError) as exc:
            values[key] = None
            errors[key] = str(exc)
    return values, errors


def metadata(sensors):
    profiles = {}
    for p in Path('/sys/class/platform-profile').glob('*'):
        profiles[read(p / 'name') or p.name] = read(p / 'profile')
    return {
        'type': 'metadata', 'schema': 1, 'started_utc': utcnow(),
        'model': read(Path('/sys/class/dmi/id/product_name')),
        'bios': read(Path('/sys/class/dmi/id/bios_version')),
        'kernel': platform.release(), 'sensors': sensors, 'profiles': profiles,
        'no_turbo': read(Path('/sys/devices/system/cpu/intel_pstate/no_turbo')),
        'note': 'Read-only; no SMM polling. No process names, URLs, or serial numbers.',
    }


def utcnow():
    return datetime.now(timezone.utc).isoformat()


def record(args):
    sensors = discover()
    if not any(s['driver'] == 'dell_ddv' and s['unit'] == 'RPM' for s in sensors.values()):
        raise SystemExit('No Dell DDV fan readings available; refusing a misleading capture.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation prevents overwriting another recording.
    with args.output.open('x') as out:
        out.write(json.dumps(metadata(sensors)) + '\n')
        out.flush()
        start = time.monotonic()
        previous_ticks = cpu_ticks()
        previous_fans = {}
        first = True
        try:
            while time.monotonic() - start < args.duration:
                tick = time.monotonic()
                values, errors = snapshot(sensors)
                current = cpu_ticks()
                total, idle = (a - b for a, b in zip(current, previous_ticks))
                cpu = None if first or total <= 0 else round(100 * (1 - idle / total), 2)
                previous_ticks, first = current, False
                sample = {
                    'type': 'sample', 'utc': utcnow(),
                    'elapsed_s': round(time.monotonic() - start, 3),
                    'read_duration_s': round(time.monotonic() - tick, 3),
                    'cpu_busy_pct_all_cores': cpu,
                    'values': values, 'errors': errors,
                }
                out.write(json.dumps(sample) + '\n')
                out.flush()
                for key, info in sensors.items():
                    if info['unit'] != 'RPM':
                        continue
                    rpm = values[key]
                    running = None if rpm is None else rpm > 0
                    if running is not None and previous_fans.get(key) is not None and running != previous_fans[key]:
                        print(f"{sample['utc']} {info['label']}: {rpm} RPM", flush=True)
                    previous_fans[key] = running
                time.sleep(max(0, min(args.interval - (time.monotonic() - tick),
                                      args.duration - (time.monotonic() - start))))
        except KeyboardInterrupt:
            print('Capture stopped; completed samples retained.')
    print(f'Recorded {args.output}')


def summarize(path):
    with path.open() as inp:
        meta = json.loads(next(inp))
        sensors = meta['sensors']
        ranges, previous, events = {}, {}, []
        count, error_count, elapsed = 0, 0, 0
        for line in inp:
            if not line.strip():
                continue
            row = json.loads(line)
            count += 1
            elapsed = row['elapsed_s']
            error_count += len(row['errors'])
            for key, value in row['values'].items():
                if value is not None:
                    low, high = ranges.get(key, (value, value))
                    ranges[key] = min(low, value), max(high, value)
                if sensors[key]['unit'] != 'RPM':
                    continue
                running = None if value is None else value > 0
                if running is not None and previous.get(key) is not None and running != previous[key]:
                    events.append({
                        'elapsed_s': elapsed, 'fan': sensors[key]['label'],
                        'event': 'start' if running else 'stop', 'rpm': value,
                        'cpu_busy_pct_all_cores': row['cpu_busy_pct_all_cores'],
                        'temperatures_C': {
                            k: v for k, v in row['values'].items()
                            if sensors[k]['unit'] == 'C'
                        },
                    })
                previous[key] = running
    return {
        'samples': count, 'elapsed_s': elapsed, 'sensor_read_errors': error_count,
        'ranges': {k: {'label': sensors[k]['label'], 'unit': sensors[k]['unit'],
                       'min': v[0], 'max': v[1]} for k, v in ranges.items()},
        'fan_transitions': events,
        'limitations': 'Sampled transitions only; initial spinning fans are not counted as starts. '
                       'Missing readings break continuity. Temperatures at transitions do not prove causation. '
                       'This cannot predict temperatures under a different fan policy.',
    }


def positive(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError('must be a finite positive number')
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    capture = sub.add_parser('record')
    capture.add_argument('--duration', type=positive, default=900)
    capture.add_argument('--interval', type=positive, default=2)
    capture.add_argument('--output', type=Path, required=True)
    report = sub.add_parser('summarize')
    report.add_argument('input', type=Path)
    args = parser.parse_args()
    if args.command == 'record':
        if args.interval < 1:
            parser.error('interval must be at least 1 second to limit polling overhead')
        record(args)
    else:
        print(json.dumps(summarize(args.input), indent=2))


if __name__ == '__main__':
    main()
