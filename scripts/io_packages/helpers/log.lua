local LOG_FILE_NAME = "khrecom_lua_library.log"

local log_path = nil

local function find_log_path()
    if type(SCRIPT_PATH) ~= "string" then
        return LOG_FILE_NAME
    end
    return SCRIPT_PATH .. "/io_packages/" .. LOG_FILE_NAME
end

local function log_debug(message)
    if log_path == nil then
        log_path = find_log_path()
    end
    local file = io.open(log_path, "a")
    if file == nil then
        return
    end
    file:write("[" .. os.date("%H:%M:%S") .. "] " .. message .. "\n")
    file:close()
end

return {
    log_debug = log_debug
}
