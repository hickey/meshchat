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

require("posix.fcntl")
require("posix.unistd")
require("uci")

version = '1.02'

function die(msg)
    os.exit(-1)
end

function capture(cmd)
    local f = io.popen(cmd)
    if not f then
        return ""
    end
    local output = f:read("*a")
    f:close()
    return output
end

function node_name()
    return uci.cursor("/etc/local/uci"):get("hsmmmesh", "settings", "node") or ""
end

function zone_name()
    for line in io.lines("/etc/config/services")
    do
        local zone = line:match(":8080/meshchat|tcp|(.+)")
        if zone then
            return zone
        end
    end
    return "MeshChat"
end

messages_db_file = messages_db_file_orig .. "." .. zone_name()

local lock_fd
function get_lock()
    lock_fd = posix.fcntl.open(lock_file, posix.fcntl.O_CREAT + posix.fcntl.O_RDWR)
    local lock = {
        l_type = posix.fcntl.F_WRLCK,
        l_whence = posix.fcntl.SEEK_SET,
        l_start = 0,
        l_len = 0
    }
    if posix.fcntl.fcntl(lock_fd, posix.fcntl.F_SETLKW, lock) ~= 0 then
        print([[{"status":500, "response":"Could not get lock"}]])
        die("count not get lock")
    end
end

function release_lock()
    local unlock = {
        l_type = posix.fcntl.F_UNLCK,
        l_whence = posix.fcntl.SEEK_SET,
        l_start = 0,
        l_len = 0
    }
    posix.fcntl.fcntl(lock_fd, posix.fcntl.F_SETLK, unlock)
    posix.unistd.close(lock_fd)
end

function file_md5(file)
    if not nixio.fs.stat(file) then
        return ""
    end
    local output = capture("md5sum " .. file:gsub(" ", "\\ ")):match("^(%S+)%s")
    return output and output or ""
end

function get_messages_db_version()
    for line in io.lines(messages_version_file)
    do
        return line:gsub("\n$", "")
    end
end

function save_messages_db_version()
    local f = io.open(messages_version_file, "w")
    f:write(get_messages_version_file() .. "\n")
    f:close()
    nixio.fs.chmod(messages_version_file, "666")
end

function get_messages_version_file()
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

function hash()
    return capture("echo " ..  os.time() .. math.random(99999) .. " | md5sum"):sub(1, 8)
end

function sort_and_trim_db()
    local unused_count = max_messages_db_size
    local messages = {}
    for line in io.lines(messages_db_file)
    do
        local id, epoch = line:match("^(%S+)\t(%S+)\t")
        messages[#messages + 1] = {
            epoch = tonumber(epoch),
            id = tonumber(id, 16),
            line = line
        }
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

function file_storage_stats()
    local lines = capture("df -k " .. local_files_dir)
    local blocks, used, available, perc = lines:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%")
    used = tonumber(used) * 1024
    available = tonumber(available) * 1024
    local total = used + available

    get_lock()

    local local_files_bytes = 0
    for file in nixio.fs.dir(local_files_dir)
    do
        local_files_bytes = local_files_bytes + nixio.fs.stat(local_files_dir .. "/" .. file).size
    end

    release_lock()

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

function gethostbyname(hostname)
    return capture("nslookup " .. hostname):match("Address 1:%s*([%d%.]+)")
end

function node_list()
    if not nixio.fs.stat("/var/run/services_olsr") then
        return {}
    end
    local local_node = node_name():lower()
    local zone = zone_name()

    local nodes = {}
    local pattern = "http://(%S+):(%d+)/meshchat|tcp|" .. str_escape(zone) .. "%s"
    for line in io.lines("/var/run/services_olsr")
    do
        local node, port = line:match(pattern)
        if node and port then
            node = node:lower()
            if node ~= local_node then
                if port == "8080" then
                    nodes[#nodes + 1] = {
                        platform = "node",
                        node = node,
                        port = port
                    }
                else
                    nodes[#nodes + 1] = {
                        platform = "pi",
                        node = node,
                        port = port
                    }
                end
            end
        end
    end

    for _, extra in ipairs(extra_nodes)
    do
        nodes[#node + 1] = extra
    end

    return nodes
end

function str_escape(str)
	return str:gsub("%(", "%%("):gsub("%)", "%%)"):gsub("%%", "%%%%"):gsub("%.", "%%."):gsub("%+", "%%+"):gsub("-", "%%-"):gsub("%*", "%%*"):gsub("%[", "%%["):gsub("%?", "%%?"):gsub("%^", "%%^"):gsub("%$", "%%$")         
end
