--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2022 Tim Wilkinson
	Base on code (C) Trevor Paskett (see https://github.com/tpaskett)
	See Contributors file for additional contributors

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation version 3 of the License.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.

	Additional Terms:

	Additional use restrictions exist on the AREDN(TM) trademark and logo.
		See AREDNLicense.txt for more info.

	Attributions to the AREDN Project must be retained in the source code.
	If importing this code into a new or existing project attribution
	to the AREDN project must be added to the source code.

	You must not misrepresent the origin of the material contained within.

	Modified versions must be modified to attribute to the original source
	and be marked in reasonable ways as differentiate it from the original
	version

--]]

require("uci")
require("socket")

local M = {}

--- @module meshchatlib

--- Exit the program with an error message.
--
-- @tparam string msg Message to display
--
function M:die(msg)
    os.exit(-1)
end

--- Execute a command and capture the output.
--
-- @tparam string cmd Command line to execute
-- @treturn string stdout of the command
--
function M:capture(cmd)
    local f = io.popen(cmd)
    if not f then
        return ""
    end
    local output = f:read("*a")
    f:close()
    return output
end

-- TODO remove AAMM specific parts
function M:filelist(dir)
    local files = {}
    for file in io.popen("ls -1 " .. dir .. "/*.txt"):lines() do
        file = file:gsub(Config.aam_dir .. "/", "")
        table.insert(files, file)
    end
    return files
end

function M:file_exists(path)
    local f = io.open(path, "r")
    return f ~= nil and io.close(f)
end

function M:file_size(path)
    local f = io.open(path, "r")
    local size = f:seek("end")
    f:close()
    return size
end

function M:file_mtime(path)
    local proc = io.popen("ls --full-time " .. path, "r")
    local file_info = proc:read("*all")
    proc:close()
    -- -rw-r--r--    1 root     root             0 2023-09-29 00:32:22 -0400 foo

    local yr, mo, da, hr, mi, se, tz = file_info:match("[-rwx]+%s+%d+%s%w+%s+%w+%s+%d+%s(%d+)-(%d+)-(%d+)%s(%d+):(%d+):(%d+)%s([-+%d]+)%s")
    local offset = (tz / 100) * 3600
    return os.time({year=yr, month=mo, day=da, hour=hr, min=mi, sec=se}) - offset
end

function M:mkdir(path)
    os.execute('mkdir ' .. path .. ' >/dev/null 2>&1')
end

function M:unlink(path)
    os.execute('rm ' .. path .. ' >/dev/null 2>&1')
end

function M:chmod(path, mode)
    os.execute('chmod ' .. mode .. ' ' .. path .. ' >/dev/null 2>&1')
end

function M:rename(src, dest)
    os.execute('mv ' .. src .. ' ' .. dest .. ' >/dev/null 2>&1')
end

---
-- Retrieve the current node name.
--
-- This function will interogate the UCI settings to retrieve the current
-- node name stored in the `hsmmmesh` settings.
--
-- @treturn string Name of current node
--
function M:node_name()
    return uci.cursor("/etc/local/uci"):get("hsmmmesh", "settings", "node") or ""
end

---
-- Retrieve the current MeshChat zone name that the node is operating under.
--
-- @treturn string Name of MeshChat zone
--
function M:zone_name()
    local dmz_mode = uci.cursor("/etc/config.mesh"):get("aredn", "@dmz[0]", "mode")
    local servfile = "/etc/config.mesh/_setup.services.nat"
    -- LAN mode is not set to NAT
    if dmz_mode ~= "0" then
        servfile = "/etc/config.mesh/_setup.services.dmz"
    end
    if M.file_exists(servfile) then
        for line in io.lines(servfile)
        do
            local zone = line:match("^(.*)|.*|.*|.*|.*|meshchat$")
            if zone then
                return zone
            end
        end
    end
    return "MeshChat"
end

messages_db_file = messages_db_file_orig .. "." .. M.zone_name()

local lock_fd = false
function M:get_lock(lock_file)
    while (not os.execute("mkdir " .. lock_file .. " >/dev/null 2>&1")) do
        socket.select(nil, nil, 0.2)
    end
    lock_fd = true
end

function M:release_lock(lock_file)
    if (lock_fd) then
        os.execute("rmdir " .. lock_file)
        lock_fd = false
    end
end

--- Generate the MD5 sum of a file.
--
-- This under the covers relies on `md5sum` and executes `md5sum` against
-- the specified file.
--
-- @note
--   There is no checking to determine if `md5sum` is installed or
--   executable. In the future, this may change.
--
-- @tparam string file Path to file
-- @treturn string Result of `md5sum` of the file
--
function M:file_md5(file)
    if not file_exists(file) then
        return ""
    end
    local output = capture("md5sum " .. file:gsub(" ", "\\ ")):match("^(%S+)%s")
    return output and output or ""
end

function M:get_messages_db_version()
    for line in io.lines(messages_version_file)
    do
        line = line:gsub("\n$", "")
        return line
    end
end

function M:save_messages_db_version()
    local f = io.open(messages_version_file, "w")
    f:write(M.get_messages_version_file() .. "\n")
    f:close()
    M.chmod(messages_version_file, "666")
end

function M:get_messages_version_file()
    local sum = 0
    for line in io.lines(messages_db_file)
    do
        local key = line:match("^([0-9a-f]+)")
        if key then
            sum = sum + tonumber(key, 16)
        end
    end
    return sum
end

--- Generate a unique hash.
--
-- Combine the current time (epoch time) and a randomly generated number
-- between 0 - 99999 and run through `md5sum` to generate a random hash.
--
-- @note
--   There is no checking to determine if `md5sum` is installed or
--   executable. In the future, this may change.
--
-- @treturn string Generated hash value
--
function M:hash()
    return M.capture("echo " ..  os.time() .. math.random(99999) .. " | md5sum"):sub(1, 8)
end

function M:sort_and_trim_db()
    local valid_time = os.time() + valid_future_message_time
    local unused_count = max_messages_db_size
    local messages = {}
    for line in io.lines(messages_db_file)
    do
        local id, epoch = line:match("^(%x+)\t(%S+)\t")
	-- ignore messages that are too far in the future (assume they're errors)
        epoch = tonumber(epoch)
	if epoch and epoch < valid_time then
            messages[#messages + 1] = {
                epoch = epoch,
                id = tonumber(id, 16),
                line = line
            }
        end
        unused_count = unused_count - 1
    end

    table.sort(messages, function(a, b)
        if a.epoch == b.epoch then
            return a.id < b.id
        else
            return a.epoch < b.epoch
        end
    end)

    local f = io.open(messages_db_file, "w")
    for _, line in ipairs(messages)
    do
        unused_count = unused_count + 1
        if unused_count > 0 then
            f:write(line.line .. "\n")
        end
    end
    f:close()
end

function M:file_storage_stats()
    local lines = capture("df -k " .. local_files_dir)
    local blocks, used, available, perc = lines:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%")
    used = tonumber(used) * 1024
    available = tonumber(available) * 1024
    local total = used + available

    local local_files_bytes = 0
    for file in M.filelist(local_files_dir)
    do
        local_files_bytes = local_files_bytes + M.file_size(local_files_dir .. "/" .. file)
    end

    if max_file_storage - local_files_bytes < 0 then
        local_files_bytes = max_file_storage
    end

    return {
        total = total,
        used = used,
        files = local_files_bytes,
        files_free = max_file_storage - local_files_bytes,
        allowed = max_file_storage
    }
end

function M:gethostbyname(hostname)
    return capture("nslookup " .. hostname):match("Address 1:%s*([%d%.]+)")
end

function M:node_list()
    if not M.file_exists("/var/run/services_olsr") then
        return {}
    end
    local local_node = M.node_name():lower()
    local zone = M.zone_name()

    local nodes = {}
    local pattern = "http://(%S+):(%d+)/meshchat|tcp|" .. M.str_escape(zone) .. "%s"
    for line in io.lines("/var/run/services_olsr")
    do
        local node, port = line:match(pattern)
        if node and port then
            node = node:lower()
            if node ~= local_node then
                nodes[#nodes + 1] = {
                    platform = (port == "8080" and "node" or "pi"),
                    node = node,
                    port = port
                }
            end
        end
    end

    for _, extra in ipairs(extra_nodes)
    do
        nodes[#node + 1] = extra
    end

    return nodes
end

---
-- Escape percent signs.
--
-- @tparam string str String to encode
-- @treturn string Encoded string
--
function M:str_escape(str)
	return str:gsub("%(", "%%("):gsub("%)", "%%)"):gsub("%%", "%%%%"):gsub("%.", "%%."):gsub("%+", "%%+"):gsub("-", "%%-"):gsub("%*", "%%*"):gsub("%[", "%%["):gsub("%?", "%%?"):gsub("%^", "%%^"):gsub("%$", "%%$")
end


function M:getenv()
    local osEnv = {}

    for line in io.popen("set"):lines() do
        envName = line:match("^[^=]+")
        osEnv[envName] = os.getenv(envName)
    end

    return osEnv
end

return M
