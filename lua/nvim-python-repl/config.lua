local defaults = {
    execute_on_send = true,
    vsplit = true,
    spawn_command = {
        python = "ipython",
        scala = "sbt console",
        r = "radian",
        lua = "ilua",
    }
}

local function set(_, key, value)
    defaults[key] = value
end

local function get(_, key)
    return defaults[key]
end

return {
    defaults = defaults,
    get = get,
    set = set
}