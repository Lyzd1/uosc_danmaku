
-- 选项
-- 导入ass数据相关流程
local options = {
    load_more_danmaku = false,
	auto_load = false,
}


require("mp.options").read_options(options, "uosc_danmaku")

local utils = require("mp.utils")
local episodeId = nil


-- Buffer for the input string
local input_buffer = ""
local danmaku_path = mp.get_script_directory() .. "/danmaku/"


local tmp=options.auto_load
local tmp_flag=false  --标记自动装载弹幕流程是否被跑通。如果跑通，则置位为true。如果未跑通,则为false。
                      --在打开视频时flag=false，此时在使用快捷键d时会识别到tmp_flag=false,会自动调用命令执行一次autoload装载操作。




-- url编码转换
function url_encode(str)
    -- 将非安全字符转换为百分号编码
    if str then
        str = str:gsub("([^%w%-%.%_%~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
    end
    return str
end

function itable_index_of(itable, value)
    for index = 1, #itable do
        if itable[index] == value then
            return index
        end
    end
end

local platform = (function()
    local platform = mp.get_property_native("platform")
    if platform then
        if itable_index_of({ "windows", "darwin" }, platform) then
            return platform
        end
    else
        if os.getenv("windir") ~= nil then
            return "windows"
        end
        local homedir = os.getenv("HOME")
        if homedir ~= nil and string.sub(homedir, 1, 6) == "/Users" then
            return "darwin"
        end
    end
    return "linux"
end)()


-- Show OSD message to prompt user to input episode ID
function show_input_menu()
    mp.osd_message("Input Episode ID: " .. input_buffer, 10)    -- Display the current input buffer in OSD
    mp.add_forced_key_binding("BS", "backspace", handle_backspace) -- Bind Backspace to delete last character
    mp.add_forced_key_binding("Enter", "confirm", confirm_input) -- Bind Enter key to confirm input
    mp.add_forced_key_binding("Esc", "cancel", cancel_input)    -- Bind Esc key to cancel input

    -- Bind alphanumeric keys to capture user input
    for i = 0, 9 do
        mp.add_forced_key_binding(tostring(i), "input_" .. i, function()
            handle_input(tostring(i))
        end)
    end
    for i = 97, 122 do
        local char = string.char(i)
        mp.add_forced_key_binding(char, "input_" .. char, function()
            handle_input(char)
        end)
    end
end


-- Handle user input by adding characters to the buffer
function handle_input(char)
    input_buffer = input_buffer .. char
    mp.osd_message("Input Episode ID: " .. input_buffer, 10) -- Update the OSD with current input
end

-- Handle backspace to delete the last character
function handle_backspace()
    input_buffer = input_buffer:sub(1, -2)                -- Remove the last character
    mp.osd_message("Input Episode ID: " .. input_buffer, 10) -- Update the OSD
end

-- Confirm the input and process the episode ID
function confirm_input()
    mp.remove_key_binding("backspace")
    mp.remove_key_binding("confirm")
    mp.remove_key_binding("cancel")
    for i = 0, 9 do
        mp.remove_key_binding("input_" .. i)
    end
    for i = 97, 122 do
        mp.remove_key_binding("input_" .. string.char(i))
    end

    if input_buffer ~= "" then
        set_episode_id(input_buffer)
    else
        mp.osd_message("No input provided", 2)
    end
    input_buffer = "" -- Clear the input buffer
end

-- Cancel input
function cancel_input()
    mp.remove_key_binding("backspace")
    mp.remove_key_binding("confirm")
    mp.remove_key_binding("cancel")
    for i = 0, 9 do
        mp.remove_key_binding("input_" .. i)
    end
    for i = 97, 122 do
        mp.remove_key_binding("input_" .. string.char(i))
    end

    mp.osd_message("Input cancelled", 2)
    input_buffer = "" -- Clear the input buffer
end







-- 弹幕加载相关。 移除弹幕轨道
function remove_danmaku_track()
    local tracks = mp.get_property_native("track-list")
    for i = #tracks, 1, -1 do
        if tracks[i].type == "sub" and tracks[i].title == "danmaku" then
            mp.commandv("sub-remove", tracks[i].id)
            break
        end
    end
end

function show_danmaku_func()
    local tracks = mp.get_property_native("track-list")
    for i = #tracks, 1, -1 do
        if tracks[i].type == "sub" and tracks[i].title == "danmaku" then
            mp.set_property("secondary-sub-ass-override", "yes")
            mp.set_property("secondary-sid", tracks[i].id)
            break
        end
    end
end

function hide_danmaku_func()
    mp.set_property("secondary-sid", "no")
end




--读history 和 写history
function read_file(file_path)
    local file = io.open(file_path, "r") -- 打开文件，"r"表示只读模式
    if not file then
        return nil
    end
    local content = file:read("*all") -- 读取文件所有内容
    file:close()                   -- 关闭文件
    return content
end

function write_json_file(file_path, data)
    local file = io.open(file_path, "w")
    if not file then
        return
    end
    file:write(utils.format_json(data)) -- 将 Lua 表转换为 JSON 并写入
    file:close()
end


-- 获取父文件名
function get_father_directory()
    local file_path = mp.get_property("path") --获取当前视频文件的完整路径
    local cwd = mp.get_property("working-directory")
    local fname = nil
    local full_path
    if platform == "windows" then
        file_path = string.gsub(file_path, "^%.\\", "")
        if string.find(file_path, "\\") == nil then
            full_path = cwd .. "\\" .. file_path
        else
            full_path = file_path
        end
        fname = string.match(full_path, ".*\\([^\\]+)\\[^\\]+$")
    else
        file_path = string.gsub(file_path, "^%./", "")
        if string.find(file_path, "/") == nil then
            full_path = cwd .. "/" .. file_path
        else
            full_path = file_path
        end
        fname = string.match(full_path, ".*/([^/]+)/[^/]+$")
    end
    return fname
end


-- 获取当前文件名所包含的集数
function get_episode_number()
    local filename = mp.get_property("filename")
    local pattern = "(%d+)"

    -- 尝试匹配文件名中的数字
    for number in string.gmatch(filename, pattern) do
        -- 转换为数字
        local episodeNumber = tonumber(number)
        -- 最大集数1000，过滤4k和1080p
        filename = string.lower(filename)
        if
            episodeNumber
            and episodeNumber <= 1000
            and filename:sub(filename:find(number) + 0, filename:find(number) + #number + 1) ~= "4k"
            and filename:sub(filename:find(number) + 0, filename:find(number) + #number + 1) ~= "720p"
            and filename:sub(filename:find(number) + 0, filename:find(number) + #number + 1) ~= "360p"
        then
            return episodeNumber
        end
    end
end



--	写入history和读取弹幕库
--	对不同调用模式进行分流。
function set_episode_id(input,from_menu)   --设置为菜单建立
	from_menu = from_menu or false  --如果为true，则使用下面逻辑。如果为false，则不修改数据，仅加载。
    episodeId = tonumber(input)
	  
	
	-- 如果来自菜单加载弹幕，正常写入
	if from_menu then 
		local fname = get_father_directory()	--获取父文件名
		if fname ~= nil then
			local history_path = danmaku_path .. "history.json"  
			local episodeNumber=get_episode_number()   
			local history_json = read_file(history_path)
			if history_json ~= nil then
				local history = utils.parse_json(history_json)
				history[fname] = {}
				history[fname].episodeNumber=episodeNumber
				history[fname].episodeId = episodeId
				write_json_file(history_path, history)
			else
				local history = {}
				history[fname] = {}
				history[fname].episodeNumber=episodeNumber
				history[fname].episodeId = episodeId
				write_json_file(history_path, history)
			end
		end
	end	
	

	-- 读取episodeID去获取弹幕
	if options.load_more_danmaku then
			fetch_danmaku_all(episodeId) 
		else
			fetch_danmaku(episodeId)
		end

end





-- 匹配弹幕库 comment  仅匹配dandan本身弹幕库
-- 通过danmaku api（url）+id获取弹幕
-- Function to fetch danmaku from API
function fetch_danmaku(episodeId)
    local url = "https://api.dandanplay.net/api/v2/comment/" .. episodeId .. "?withRelated=true&chConvert=0"

    -- Use curl command to get the JSON data
    local req = {
        args = {
            "curl",
            "-L",
            "-X",
            "GET",
            "--header",
            "Accept: application/json",
            "--header",
            "User-Agent: MyCustomUserAgent/1.0",
            url,
        },
        cancellable = false,
    }

    mp.osd_message("弹幕加载中...", 60)

    local res = utils.subprocess(req)

    if res.status == 0 then
        local response = utils.parse_json(res.stdout)
        if response and response["comments"] then
            if response["count"] == 0 then
                mp.osd_message("该集弹幕内容为空，结束加载", 3)
                return
            end
            local success = save_json_for_factory(response["comments"])
            if success then
                convert_with_danmaku_factory()

                remove_danmaku_track()
                mp.commandv("sub-add", danmaku_path .. "danmaku.ass", "auto", "danmaku")
                show_danmaku_func()
                mp.commandv("script-message-to", "uosc", "set", "show_danmaku", "on")
                mp.osd_message("弹幕加载成功，共计" .. response["count"] .. "条弹幕", 3)
            else
                mp.osd_message("Error saving JSON file", 3)
            end
        else
            mp.osd_message("No result", 3)
        end
    else
        mp.osd_message("HTTP Request failed: " .. res.error, 3)
    end
end


-- 匹配多个弹幕库 related 包括如腾讯、优酷、b站等
function fetch_danmaku_all(episodeId)
    local comments = {}
   
    local url = "https://api.dandanplay.net/api/v2/related/" .. episodeId 

    local req = {
        args = {
            "curl",
            "-L",
            "-X",
            "GET",
            "--header",
            "Accept: application/json",
            "--header",
            "User-Agent: MyCustomUserAgent/1.0",
            url,
        },
        cancellable = false,
    }

    mp.osd_message("弹幕加载中...", 3)

    local res = utils.subprocess(req)

    if res.status ~= 0 then
        mp.osd_message("HTTP Request failed: " .. res.error, 3)
        return
    end

    local response = utils.parse_json(res.stdout)

    if not response or not response["relateds"] then
        mp.osd_message("No result", 3)
        return
    end

    for _, related in ipairs(response["relateds"]) do
        url = "https://api.dandanplay.net/api/v2/extcomment?url=" .. url_encode(related["url"])

        req = {
            args = {
                "curl",
                "-L",
                "-X",
                "GET",
                "--header",
                "Accept: application/json",
                "--header",
                "User-Agent: MyCustomUserAgent/1.0",
                url,
            },
            cancellable = false,
        }


        --mp.osd_message("正在从此地址加载弹幕：" .. related["url"], 60)  
		mp.osd_message("正在从第三方库装填弹幕", 2)  

        res = utils.subprocess(req)

        if res.status ~= 0 then
            mp.osd_message("HTTP Request failed: " .. res.error, 3)
            return
        end

        local response_comments = utils.parse_json(res.stdout)

        if not response_comments or not response_comments["comments"] then
            mp.osd_message("No result", 3)
            goto continue
        end

        if response_comments["count"] == 0 then
            local start = os.time()
            while os.time() - start < 1 do
                -- 空循环，等待 1 秒
            end

            res = utils.subprocess(req)
            response_comments = utils.parse_json(res.stdout)
        end

        for _, comment in ipairs(response_comments["comments"]) do
            table.insert(comments, comment)
        end
        ::continue::
    end

	-- 	如果成功加载第三方弹幕库，就不适用danmaku
	if comments == nil then 
		url = "https://api.dandanplay.net/api/v2/comment/" .. episodeId .. "?withRelated=false&chConvert=0"

		req = {
			args = {
				"curl",
				"-L",
				"-X",
				"GET",
				"--header",
				"Accept: application/json",
				"--header",
				"User-Agent: MyCustomUserAgent/1.0",
				url,
			},
			cancellable = false,
		}

		mp.osd_message("正在从弹弹Play库装填弹幕", 1)

		res = utils.subprocess(req)

		if res.status ~= 0 then
			mp.osd_message("HTTP Request failed: " .. res.error, 3)
			return
		end

		response = utils.parse_json(res.stdout)

		if not response or not response["comments"] then
			mp.osd_message("No result", 3)
			return
		end

		for _, comment in ipairs(response["comments"]) do
			table.insert(comments, comment)
		end

		if #comments == 0 then
			mp.osd_message("该集弹幕内容为空，结束加载", 3)
			return
		end
	end		

    local success = save_json_for_factory(comments)
    if success then
        convert_with_danmaku_factory()

        remove_danmaku_track()
        mp.commandv("sub-add", danmaku_path .. "danmaku.ass", "auto", "danmaku")
        show_danmaku_func()
        mp.commandv("script-message-to", "uosc", "set", "show_danmaku", "on")
        mp.osd_message("弹幕加载成功，共计" .. #comments .. "条弹幕", 3)
    else
        mp.osd_message("Error saving JSON file", 3)
    end
end



--通过输入源url获取弹幕库 
function add_danmaku_source(query)
    local url = "https://api.dandanplay.net/api/v2/extcomment?url=" .. url_encode(query)

    local req = {
        args = {
            "curl",
            "-L",
            "-X",
            "GET",
            "--header",
            "Accept: application/json",
            "--header",
            "User-Agent: MyCustomUserAgent/1.0",
            url,
        },
        cancellable = false,
    }

    mp.osd_message("弹幕加载中...", 60)

    local res = utils.subprocess(req)

    if res.status ~= 0 then
        mp.osd_message("HTTP Request failed: " .. res.error, 3)
        return
    end

    local response = utils.parse_json(res.stdout)

    if not response or not response["comments"] then
        mp.osd_message("此源弹幕无法加载", 3)
        return
    end

    local new_comments = response["comments"]
    local add_count = response["count"]

    if add_count == 0 then
        mp.osd_message("服务器无缓存数据，再次尝试请求", 60)

        local start = os.time()
        while os.time() - start < 2 do
            -- 空循环，等待 1 秒
        end

        res = utils.subprocess(req)
        response = utils.parse_json(res.stdout)
        new_comments = response["comments"]
        add_count = response["count"]
    end

    if add_count == 0 then
        mp.osd_message("此源弹幕为空，结束加载", 3)
        return
    end

    new_comments = convert_json_for_merge(new_comments)

    local old_comment_path = danmaku_path .. "danmaku.json"
    local comments = read_file(old_comment_path)

    if comments == nil then
        comments = {}
    else
        comments = utils.parse_json(comments)
    end

    for _, comment in ipairs(new_comments) do
        table.insert(comments, comment)
    end

    local json_filename = danmaku_path .. "danmaku.json"
    local json_file = io.open(json_filename, "w")

    if json_file then
        json_file:write("[\n")
        for _, comment in ipairs(comments) do
            local json_entry = string.format('{"c":"%s","m":"%s"},\n', comment["c"], comment["m"])
            json_file:write(json_entry)
        end
        json_file:write("]")
        json_file:close()
    else
        mp.osd_message("Error saving JSON file", 3)
    end

    convert_with_danmaku_factory()
    remove_danmaku_track()
    mp.commandv("sub-add", danmaku_path .. "danmaku.ass", "auto", "danmaku")
    show_danmaku_func()
    mp.commandv("script-message-to", "uosc", "set", "show_danmaku", "on")
    mp.osd_message("弹幕加载成功，添加了" .. add_count .. "条弹幕，共计" .. #comments .. "条弹幕", 3)
end




function convert_json_for_merge(comments)
    local content = {}
    for _, comment in ipairs(comments) do
        local p = comment["p"]
        if p then
            local fields = split(p, ",")
            local c_value = string.format(
                "%s,%s,%s,25,,,",
                fields[1], -- first field of p to first field of c
                fields[3], -- third field of p to second field of c
                fields[2] -- second field of p to third field of c
            )
            local m_value = comment["m"]

            m_value = escape_json_string(m_value)

            table.insert(content, { ["c"] = c_value, ["m"] = m_value })
        end
    end
    return content
end



-- 使用factory将弹幕转换为json
function save_json_for_factory(comments)
    local json_filename = danmaku_path .. "danmaku.json"
    local json_file = io.open(json_filename, "w")

    if json_file then
        json_file:write("[\n")
        for _, comment in ipairs(comments) do
            local p = comment["p"]
            if p then
                local fields = split(p, ",")
                local c_value = string.format(
                    "%s,%s,%s,25,,,",
                    fields[1], -- first field of p to first field of c
                    fields[3], -- third field of p to second field of c
                    fields[2] -- second field of p to third field of c
                )
                local m_value = comment["m"]

                m_value = escape_json_string(m_value)

                -- Write the JSON object as a single line, no spaces or extra formatting
                local json_entry = string.format('{"c":"%s","m":"%s"},\n', c_value, m_value)
                json_file:write(json_entry)
            end
        end
        json_file:write("]")
        json_file:close()
        return true
    end

    return false
end

--将json文件又转换为ass文件。
-- Function to convert JSON file using DanmakuFactory
function convert_with_danmaku_factory()
    local bin = platform == "windows" and "DanmakuFactory.exe" or "DanmakuFactory"
    danmaku_factory_path = os.getenv("DANMAKU_FACTORY") or mp.get_script_directory() .. "/bin/" .. bin
    local cmd = {
        danmaku_factory_path,
        "-o",
        danmaku_path .. "danmaku.ass",
        "-i",
        danmaku_path .. "danmaku.json",
		--字体大小
		"--fontsize",
		"40",
		-- 字体描边深度 0-4
		"--outline",
		"1",
		-- 粗体字
		"--bold",
		"true",
		-- 滚动弹幕通过屏幕的时间为xx秒
		"--scrolltime",
		"20",
		-- 字体透明度
		-- "--opacity",
		--"70",
		-- 弹幕重叠  
		"--density",
		"-1",
		-- 全部弹幕的显示范围  0.0-1.0   |  滚动弹幕：--scrollarea 
		"--displayarea",
		"0.2",
		"--ignore-warnings",  
    }

    utils.subprocess({ args = cmd })
end

function escape_json_string(str)
    -- 将 JSON 中需要转义的字符进行替换
    str = str:gsub("\\", "\\\\") -- 反斜杠
    str = str:gsub('"', '\\"') -- 双引号
    str = str:gsub("\b", "\\b") -- 退格符
    str = str:gsub("\f", "\\f") -- 换页符
    str = str:gsub("\n", "\\n") -- 换行符
    str = str:gsub("\r", "\\r") -- 回车符
    str = str:gsub("\t", "\\t") -- 制表符
    return str
end

-- Utility function to split a string by a delimiter
function split(str, delim)
    local result = {}
    for match in (str .. delim):gmatch("(.-)" .. delim) do
        table.insert(result, match)
    end
    return result
end

mp.register_script_message("show-input-menu", show_input_menu)

local rm1 = danmaku_path .. "danmaku.json"
local rm2 = danmaku_path .. "danmaku.ass"
os.remove(rm1)
os.remove(rm2)





-- 自动加载上次匹配的弹幕
function auto_load_danmaku()
	tmp_flag=false
	if tmp then 
		local fname = get_father_directory()
		if fname ~= nil then
			local history_path = danmaku_path .. "history.json"
			local history_json = read_file(history_path)
			if history_json ~= nil then
				local history = utils.parse_json(history_json)
				-- 1.判断父文件名是否存在
				local history_fname = history[fname]
				if history_fname ~= nil then
					--2.如果存在，则获取number和id
					local history_number=history[fname].episodeNumber
					local history_id = history[fname].episodeId  
					local playing_number = get_episode_number()
					local x=playing_number - history_number  --获取集数差值
					local tmp_id = tostring(x+history_id)			
					mp.osd_message("自动加载上次匹配的弹幕", 60)
					set_episode_id(tmp_id)
				end
			end
			tmp_flag=true  --执行获取弹幕操作后，置位为true
		end
	end
end


function write_flag()
    --打开文件
    local file = io.open("./portable_config/script-opts/uosc_danmaku.conf", "r")
    if not file then
        print("无法打开文件")
        return
    end	

    -- 读取文件内容
    local content = file:read("*all")
    file:close()

    -- 查找flag字段
    local flag_line = string.match(content, "auto_load=(%w+)")
    if not flag_line then
        mp.osd_message("未找到auto_load字段", 3)
        return
    end

    -- 切换flag值
    local new_flag = flag_line == "yes" and "no" or "yes"

    -- 替换文件中的flag值
    local new_content = string.gsub(content, "auto_load=(%w+)", "auto_load=" .. new_flag)

    -- 保存修改后的文件内容
    local new_file = io.open("./portable_config/script-opts/uosc_danmaku.conf", "w")
    if not new_file then
        mp.osd_message("auto_load无法写入", 3)
        return
    end
    new_file:write(new_content)
    new_file:close()

end




-- 定义一个函数来切换启动和取消启动状态
-- 1.写入记录flag状态。(修改本地文件的auto_load值)
-- 2.翻转tmp，并且识别tmp_flag
-- 3.做对应操作
function toggle_auto_load()
	write_flag()
	tmp = not tmp
	if tmp then
		if tmp_flag then 
		mp.osd_message("开启自动装载", 2)
		show_danmaku_func()
        mp.commandv("script-message-to", "uosc", "set", "show_danmaku", "on")
		else 
		mp.osd_message("开启自动装载", 2)
		mp.commandv("script-message", "auto_load_danmaku")
		show_danmaku_func()
        mp.commandv("script-message-to", "uosc", "set", "show_danmaku", "on")
		end
	else 
		mp.osd_message("关闭自动装载", 2)
		hide_danmaku_func()
        mp.commandv("script-message-to", "uosc", "set", "show_danmaku", "off")	
	end 
end


-- 打开新文件时，总是执行。
mp.register_event("start-file", auto_load_danmaku)
-- 绑定函数
mp.register_script_message("auto_load_danmaku", auto_load_danmaku)
-- 绑定快捷键
mp.add_forced_key_binding("d", "toggle_auto_load", toggle_auto_load)



