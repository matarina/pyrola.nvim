#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export PYROLA_TEST_PYTHON="${PYROLA_TEST_PYTHON:-$PWD/.venv/bin/python}"
test_state=$(mktemp -d)
trap 'rm -rf "$test_state"' EXIT HUP INT TERM
export JUPYTER_DATA_DIR="$test_state/jupyter"
export JUPYTER_RUNTIME_DIR="$test_state/runtime"
export XDG_CONFIG_HOME="$test_state/config"
export XDG_DATA_HOME="$test_state/data"
export XDG_STATE_HOME="$test_state/state"
export XDG_CACHE_HOME="$test_state/cache"
"$PYROLA_TEST_PYTHON" -m ipykernel install --user --name python3
"$PYROLA_TEST_PYTHON" -m unittest discover -s tests -p 'test_*.py'
nvim --headless -u NONE -l tests/image_protocol.lua
nvim --headless -u NONE -l tests/inline_protocol.lua
nvim --headless -u NONE -l tests/rpc.lua
nvim --headless -u NONE -l tests/integration.lua
nvim --headless -u NONE -l tests/keymaps.lua
nvim --headless -u NONE -l tests/demo_config.lua
