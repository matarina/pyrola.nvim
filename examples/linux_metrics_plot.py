"""Sample real Linux CPU/memory metrics and save a chart and raw data."""
import csv
import json
import os
import time
from datetime import datetime
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

output = Path(os.environ.get("PYROLA_PLOT_OUTPUT", "artifacts/linux-python-plot")).resolve()
output.mkdir(parents=True, exist_ok=True)

def cpu_ticks():
    values = [int(value) for value in Path("/proc/stat").read_text().splitlines()[0].split()[1:]]
    # Guest ticks are already included in user/nice, so don't double-count them.
    return sum(values[:8]), values[3] + values[4]

def memory_gib():
    info = {line.split(':')[0]: int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines()}
    return (info['MemTotal'] - info['MemAvailable']) / 1024**2, info['MemTotal'] / 1024**2

print('Sampling real /proc CPU and memory metrics for 12 seconds...', flush=True)
previous_total, previous_idle = cpu_ticks()
start = time.monotonic()
rows = []
for index in range(24):
    time.sleep(max(0, start + (index + 1) * 0.5 - time.monotonic()))
    total, idle = cpu_ticks()
    delta = total - previous_total
    cpu = 100 * (1 - (idle - previous_idle) / delta) if delta else 0
    used, capacity = memory_gib()
    rows.append((time.monotonic() - start, cpu, used))
    previous_total, previous_idle = total, idle

with (output / 'metrics.csv').open('w', newline='') as stream:
    writer = csv.writer(stream)
    writer.writerow(['elapsed_seconds', 'cpu_percent', 'memory_used_gib'])
    writer.writerows(rows)

values = np.asarray(rows)
elapsed, cpu, memory = values.T
plt.rcParams.update({'font.size': 11, 'axes.spines.top': False, 'axes.spines.right': False})
fig, axes = plt.subplots(2, 1, figsize=(10, 6.5), sharex=True, layout='constrained')
fig.suptitle('Live Linux system metrics', fontsize=19, fontweight='bold', x=0.075, ha='left')
axes[0].plot(elapsed, cpu, color='#2563eb', marker='o', markersize=3, linewidth=1.8)
axes[0].fill_between(elapsed, cpu, color='#2563eb', alpha=0.10)
axes[0].axhline(cpu.mean(), color='#334155', linestyle='--', linewidth=1, label=f'Mean {cpu.mean():.1f}%')
axes[0].set(ylabel='CPU usage (%)', ylim=(0, max(25, cpu.max() * 1.3)))
axes[0].legend(loc='upper right', frameon=False)
axes[1].plot(elapsed, memory, color='#0d9488', marker='o', markersize=3, linewidth=1.8)
axes[1].set(ylabel='Memory used (GiB)', xlabel='Elapsed time (seconds)')
axes[1].set_ylim(memory.min() - 0.1, memory.max() + 0.1)
for axis in axes:
    axis.grid(axis='y', color='#e2e8f0')
    axis.set_axisbelow(True)
axes[0].set_title(f'{datetime.now().astimezone():%Y-%m-%d %H:%M %Z}  |  {os.cpu_count()} logical CPUs  |  {capacity:.1f} GiB RAM', loc='left', fontsize=10, color='#64748b', pad=12)
fig.savefig(output / 'linux_metrics.png', dpi=180, facecolor='white')
fig.savefig(output / 'linux_metrics.pdf', facecolor='white')
summary = {'samples': len(rows), 'duration_seconds': float(elapsed[-1]), 'cpu_mean_percent': float(cpu.mean()), 'cpu_peak_percent': float(cpu.max()), 'memory_mean_gib': float(memory.mean()), 'memory_total_gib': capacity}
(output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
print(f'Saved PNG, PDF, and CSV in {output}', flush=True)
plt.show()
print('PYROLA_PLOT_COMPLETE', flush=True)
