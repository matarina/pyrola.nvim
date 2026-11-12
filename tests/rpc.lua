vim.opt.rtp:prepend(vim.fn.getcwd())
local rpc = require("pyrola.rpc")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/rplugin/python3", "p")
vim.fn.writefile(vim.split([[
import json, sys
for line in sys.stdin:
    req = json.loads(line)
    if req['method'] == 'exit':
        sys.stderr.write('fixture server failed\n')
        sys.stderr.flush()
        sys.exit(1)
    if req['method'] == 'timeout':
        continue
    sys.stdout.write('null\n42\nnot json\n')
    sys.stdout.write(json.dumps({'id': req['id'], 'result': 'ok', 'error': None}) + '\n')
    sys.stdout.flush()
]], "\n"), temp .. "/rplugin/python3/server.py")
local function test()
    local python = assert(vim.env.PYROLA_TEST_PYTHON)
    assert(rpc.start(python, temp))
    local result, err = rpc.request("echo", {})
    assert(result == "ok" and not err, vim.inspect({result, err}))
    local started = vim.uv.hrtime()
    result, err = rpc.request("exit", {}, 3000)
    assert(not result and err:find("fixture server failed", 1, true), tostring(err))
    assert((vim.uv.hrtime() - started) / 1e6 < 2000, "Exit waited for full request timeout")
    assert(rpc.start(python, temp))
    rpc.stop()
    assert(rpc.start(python, temp)) -- old exit callback must not clear the new job
    result, err = rpc.request("echo", {})
    assert(result == "ok" and not err, tostring(err))
    result, err = rpc.request("timeout", {}, 50)
    assert(not result and err == "request timed out")
    result, err = rpc.request("echo", {})
    assert(result == "ok" and not err, tostring(err))
    print("PASS: RPC protocol, failure propagation, restart race, timeout recovery")
end
local ok, err = xpcall(test, debug.traceback)
rpc.stop()
vim.fn.delete(temp, "rf")
if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
end
vim.cmd("qa!")
