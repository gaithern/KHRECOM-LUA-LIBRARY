canExecute = false
gameVersionName = nil

local function is_egs_version()
    if ReadByte(0x4E6C80) == 15 then
        return true
    end
    if ReadByte(0x4E6AC0) == 242 then
        return true
    end
    return false
end

local function is_steam_version()
    if ReadByte(0x4E7040) == 15 then
        return true
    end
    if ReadByte(0x4E6DC0) == 77 then
        return true
    end
    return false
end

local function import_version_file(file_name)
    local loaded = pcall(require, file_name)
    if loaded then
        ConsolePrint("Running with " .. file_name .. "!")
        return true
    end
    local error_banner = "\n\n!!!!!!!! IMPORT ERROR !!!!!!!!\n\n"
    local message = file_name .. ".lua missing, get it from the Github!\nMissing file is from the io_packages folder."
    ConsolePrint(error_banner .. message .. error_banner)
    return false
end

if is_egs_version() then
    gameVersionName = "EGSGlobal"
elseif is_steam_version() then
    gameVersionName = "SteamGlobal"
end

if gameVersionName ~= nil then
    ConsolePrint("RE:CoM detected, version " .. gameVersionName)
    local version_loaded = import_version_file(gameVersionName)
    local locations_loaded = import_version_file("memory_locations")
    if version_loaded and locations_loaded then
        canExecute = true
    end
end

if not canExecute then
    ConsolePrint("\n\n!!!!!!!! VERSION ERROR !!!!!!!!\n\nVersion check failed, this RE:CoM version is not supported")
end
