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
    local fh = nixio.open(lock_file, nixio.open_flags("creat", "excl"))
    if not fh then
        print([[{"status":500, "response":"Could not get lock"}]])
        die("count not get lock")
    end
    fh:close()
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

function sort_db()
    local messages = {}
    for line in io.lines(messages_db_file)
    do
        local id, epoch = line:match("^(%S+)\t(%S+)\t")
        messages[#messages + 1] = {
            epoch = tonumber(epoch),
            id = tonumber(id, 16),
            line = line
        }
    end

    table.sort(messages, function(a, b) return a.epoch < b.epoch or a.id < b.id end)

    local f = io.open(messages_db_file, "w")
    for _, line in ipairs(messages)
    do
        f:write(line.line .. "\n")
    end
    f:close()
end

function trim_db()
    local line_count = 0
    for line in io.lines(messages_db_file)
    do
       line_count = line_count + 1
    end

    if line_count > max_messages_db_size then
        local f = io.open(meshchat_path .. "/shrink_messages", "w")
        if not f then
            die("cannot trim db")
        end
        local lines_to_trim = line_count - max_messages_db_size
        local line_count = 1
        for line in io.lines(messages_db_file)
        do
            if line_count > lines_to_trim then
                print(line .. "\n")
            end
            line_count = line_count + 1
        end
        f:close()
    end

    nixio.fs.remove(messages_db_file)
    local fi = io.open(meshchat_path .. "/shrink_messages", "r")
    local fo = io.open(messages_db_file, "w")
    fo:write(fi:read("*a"))
    fi:close()
    fo:close()
    nixio.fs.remove(meshchat_path .. "/shrink_messages")
    nixio.fs.chmod(messages_db_file, "666")
end

function file_storage_stats()
    local lines = capture("df -k " .. local_files_dir)
    local blocks, used, available, perc = lines[2]:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%")
    used = used * 1024
    available = available * 1024
    local total = user + available


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
