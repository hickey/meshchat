local aredn_info = require("aredn.info")

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
    return aredn_info.get_nvram("node")
end

function zone_name()
    for line in io.lines("/var/run/services_olsr")
    do
        local zone = line:match(":8080/meshchat|tcp|(%S+)%s+# my own")
        if zone then
            return zone
        end
    end
    return "MeshChat"
end

messages_db_file = messages_db_file_orig .. "." .. zone_name()

function get_lock()
    for _ = 1,5
    do
        local fh = nixio.open(lock_file, nixio.open_flags("creat", "excl"))
        if fh then
            fh:close()
            return
        end
        nixio.nanosleep(0, 500000000)
    end
    print([[{"status":500, "response":"Could not get lock"}]])
    die("count not get lock")
end

function release_lock()
    nixio.fs.remove(lock_file)
end

function file_md5(file)
    if not nixio.fs.stat(file) then
        return ""
    end
    local output = capture("md5sum " .. file):match("^(%S+)%s")
    return output and output or ""
end

function get_messages_db_version()
    for line in io.lines(messages_version_file)
    do
        return line:chomp()
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
        local_files_bytes = local_files_bytes + nixio.fs.stat(local_files_dir .. "/" .. dir).size
    end

    release_lock()

    if max_file_storage - local_files_bytes < 0 then
        local_files_bytes = max_file_storage
    end

    return {
        total = total,
        used = used,
        files = local_files_bytes,
        file_free = max_file_storage - local_files_bytes,
        allowed = max_file_storage
    }
end

function gethostbyname(hostname)
    return capture("nslookup " .. hostname):match("Address 1:%s*([%d%.]+)")
end

function node_list()
    local local_node = node_name()
    local zone = zone_name()

    local nodes = {}
    local pattern = "http://(%S+):(%d+)/meshchat|tcp|" .. zone .. "%s"
    for line in io.lines("/var/run/services_olsr")
    do
        local node, port = line:match(pattern)
        if node and port then
            if port == "8080" then
                nodes[#nodes + 1] = {
                    platform = "node",
                    node = node:lower(),
                    port = port
                }
            else
                nodes[#nodes + 1] = {
                    platform = "pi",
                    node = node:lower(),
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
