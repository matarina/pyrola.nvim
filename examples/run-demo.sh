#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export PYROLA_DEMO_ROOT="$PWD"
export PYROLA_PLOT_OUTPUT="$PWD/artifacts/linux-python-plot"
exec kitty --title 'Pyrola Python Plot' nvim -u "$PWD/examples/demo-init.lua" "$PWD/examples/linux_metrics_plot.py"
