-- 引入模块
local utils = require("mp.utils")
require("api")


function get_animes(query) --query是动漫的部分名称
    local encoded_query = url_encode(query)

    local url = "https://api.dandanplay.net/api/v2/search/episodes"
    local params = "anime=" .. encoded_query
    local full_url = url .. "?" .. params

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
            full_url,
        },
        cancellable = false,
    }

    mp.osd_message("加载数据中...", 60)

    local res = utils.subprocess(req)

    if res.status ~= 0 then
        mp.osd_message("HTTP Request failed: " .. res.error, 3)
    end

    local response = utils.parse_json(res.stdout) --stdout标准输出流

    if not response or not response.animes then
        mp.osd_message("无结果", 3)
        return
    end

    mp.osd_message("", 0)

-- 将动漫列表获取到的动漫前缀+episodeId+episodeTitle封存在items。
    local items = {}
    for _, anime in ipairs(response.animes) do
        table.insert(items, {
            title = anime.animeTitle,
			-- value所包含的信息只有在被选中时才会执行。
            value = {
                "script-message-to",
                mp.get_script_name(),
                "search-episodes-event",
                utils.format_json(anime.episodes),    --episodes包含了episodeId和episodeTitle
            },
        })
    end

-- 依据items参数创建一个二级菜单，submit绑定search-anime-event事件
    local menu_props = {
        type = "menu_anime",
        title = "在此处输入动画名称",
        search_style = "palette",
        search_debounce = "submit",
        on_search = { "script-message-to", mp.get_script_name(), "search-anime-event" },
        footnote = "使用enter或ctrl+enter进行搜索",
        search_suggestion = query,
        items = items,
    }
    local json_props = utils.format_json(menu_props)
    mp.commandv("script-message-to", "uosc", "open-menu", json_props)
end


-- 什么时候使用get_episodes
function get_episodes(episodes)
-- 将一部动漫的title名字所对应的所有集数组成表items
    local items = {}
    for _, episode in ipairs(episodes) do
        table.insert(items, {
            title = episode.episodeTitle,
            value = { "script-message-to", mp.get_script_name(), "load-danmaku", episode.episodeId },
            keep_open = false,
            selectable = true,
        })
    end

--通过items创建集数的三级菜单
    local menu_props = {
        type = "menu_episodes",
        title = "剧集信息",
        search_style = "disabled",
        items = items,
    }
    local json_props = utils.format_json(menu_props)
    mp.commandv("script-message-to", "uosc", "open-menu", json_props)
end

-- 打开输入菜单  ，依据items创建一个一级菜单
function open_input_menu()
    local menu_props = {
        type = "menu_danmaku",
        title = "在此处输入动画名称",
        search_style = "palette",
        search_debounce = "submit",
        on_search = { "script-message-to", mp.get_script_name(), "search-anime-event" },
        footnote = "使用enter或ctrl+enter进行搜索", --没太大用处
        items = {
            {
                value = "",
                hint = "使用enter或ctrl+enter进行搜索",
                keep_open = true,
                selectable = false,
                align = "center",
            },
        },
    }
    local json_props = utils.format_json(menu_props)
    mp.commandv("script-message-to", "uosc", "open-menu", json_props)
end

function open_add_menu()
    local menu_props = {
        type = "menu_source",
        title = "在此输入源地址url",
        search_style = "palette",
        search_debounce = "submit",
        on_search = { "script-message-to", mp.get_script_name(), "add-source-event" },
        footnote = "使用enter或ctrl+enter进行搜索",
        items = {
            {
                value = "",
                hint = "使用enter或ctrl+enter进行搜索",
                keep_open = true,
                selectable = false,
                align = "center",
            },
        },
    }
    local json_props = utils.format_json(menu_props)
    mp.commandv("script-message-to", "uosc", "open-menu", json_props)
end



-- 添加了一个弹幕搜索按钮  open_search_danmaku_menu作为关键语句
mp.commandv(
    "script-message-to",
    "uosc",
    "set-button",
    "danmaku",
    utils.format_json({
        icon = "search",
        tooltip = "弹幕搜索",
        command = "script-message open_search_danmaku_menu",
    })
)


--主要通过一个url手动添加该集的弹幕
mp.commandv(
    "script-message-to",
    "uosc",
    "set-button",
    "danmaku_source",
    utils.format_json({
        icon = "add_box",
        tooltip = "从源添加弹幕",
        command = "script-message open_add_source_menu",
    })
)




-- 1.注册一个专有名词，并绑定函数|匿名函数。 
-- 2.当该专有名词被调用时，会使用后面的函数。
-- 注册函数给 uosc 按钮使用
mp.register_script_message("open_search_danmaku_menu", open_input_menu)  --将搜索按钮与输入菜单绑定
mp.register_script_message("search-anime-event", function(query)  --query是输入的动漫名部分。
    mp.commandv("script-message-to", "uosc", "close-menu", "menu_danmaku")  --关闭输入菜单
    get_animes(query)  --将部分动漫名传参给get
end)
mp.register_script_message("search-episodes-event", function(episodes) --episodes是episodeId和episodeTitle集合
    mp.commandv("script-message-to", "uosc", "close-menu", "menu_anime")
    get_episodes(utils.parse_json(episodes)) 
end)

-- Register script message to show the input menu
mp.register_script_message("load-danmaku", function(episodeId)
    set_episode_id(episodeId,true)   --使用api.lua中的函数获取episodeid
end)




mp.register_script_message("open_add_source_menu", open_add_menu)
mp.register_script_message("add-source-event", function (query)  --确实返回了一个输入的url
    mp.commandv("script-message-to", "uosc", "close-menu", "menu_source") 
    add_danmaku_source(query)   --b站番剧链接获取的信息少了关键字，不能通过这里获取弹幕。
end)








-- 显示弹幕 on/off开关  cycle:toggle_on:show_danmaku@uosc_danmaku:on=toggle_on/off=toggle_off?弹幕开关
-- show_danmaku是调用的api方法。
mp.commandv("script-message-to", "uosc", "set", "show_danmaku", "off")  --随mpv启动
mp.register_script_message("set", function(prop, value)  
    if prop ~= "show_danmaku" then
        return
    end

    if value == "on" then
        show_danmaku_func()
    else
        hide_danmaku_func()
    end
    mp.commandv("script-message-to", "uosc", "set", "show_danmaku", value)
end)

mp.register_script_message("show_danmaku_keyboard", function()
    local has_danmaku = false
    local sec_sid = mp.get_property("secondary-sid")
    local tracks = mp.get_property_native("track-list")
    for i = #tracks, 1, -1 do
        if tracks[i].type == "sub" and tracks[i].title == "danmaku" then
            has_danmaku = true
            break
        end
    end

    if sec_sid == "no" and has_danmaku == false then
        return
    end

    if sec_sid ~= "no" then
        hide_danmaku_func()
        mp.commandv("script-message-to", "uosc", "set", "show_danmaku", "off")  
    else
        show_danmaku_func()
        mp.commandv("script-message-to", "uosc", "set", "show_danmaku", "on")
    end
	
	
end)







-- 2. 当收到来自bilibili的视频流时，自动加载弹幕 
function bilibiliauto()
    local file_path = mp.get_property('path')
    if string.find(file_path, "bilibili.com") then
        print(file_path)
		mp.commandv("script-message", "add-source-event",file_path)
    end
end

function delayed_bilibiliauto()
    mp.add_timeout(1, bilibiliauto) -- Wait for 1 second before trying to get the file_path again
end

 mp.register_event("start-file", delayed_bilibiliauto)