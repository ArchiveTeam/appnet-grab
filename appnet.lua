dofile("urlcode.lua")
dofile("table_show.lua")

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')

local allowed_strings = {}

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

start, end_ = string.match(item_value, "([0-9]+)-([0-9]+)")
for i = start, end_ do
  allowed_strings[tostring(i)] = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
     or string.match(url, "[<>\\]")
     or string.match(url, "//$")
     or string.match(url, "icons%.fallback%.css")
     or not (string.match(url, "^https?://[^/]*app%.net")
      or string.match(url, "^https?://[^/]*cloudfront%.net")) then
    return false
  end

  if item_type == "users" and string.match(url, "/posts?/") then
    return false
  end

  if item_type == "posts" and string.match(url, "^https?://files%.app%.net") then
    return true
  end

  for s in string.gmatch(url, "([0-9]+)") do
    if allowed_strings[s] == true then
      return true
    end
  end

  if item_type == "users" then
    for s in string.gmatch(url, "([a-zA-Z0-9%-%._]+)") do
      if allowed_strings[s] == true then
        return true
      end
    end
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
     and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end

  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true
  
  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    if (downloaded[url] ~= true and addedtolist[url] ~= true)
       and (allowed(url, origurl) or string.match(url, "^https?://api%.app%.net/posts/[0-9]+$")) then
      table.insert(urls, { url=string.gsub(url, "&amp;", "&") })
      addedtolist[url] = true
      addedtolist[string.gsub(url, "&amp;", "&")] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
       or string.match(newurl, "^[/\\]")
       or string.match(newurl, "^[jJ]ava[sS]cript:")
       or string.match(newurl, "^[mM]ail[tT]o:")
       or string.match(newurl, "^vine:")
       or string.match(newurl, "^android%-app:")
       or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end
  
  if allowed(url, nil) then
    html = read_file(file)

    if string.match(url, "post/[0-9]+$") then
      check("https://api.app.net/posts/" .. string.match(url, "post/([0-9]+)$"))
    end

    if item_type == "users" then
      if string.match(html, "<link>https?://alpha%.app%.net/[^<]+</link>") then
        allowed_strings[string.match(html, "<link>https?://alpha%.app%.net/([^<]+)</link>")] = true
      end
      if string.match(html, '<data%s+class="u%-photo"%s+value="https?://[^%.]+%.cloudfront%.net/[^/]+/[^/]+/[^%?]+%?[^"]+"></data>') then
        allowed_strings[string.match(html, '<data%s+class="u%-photo"%s+value="https?://[^%.]+%.cloudfront%.net/[^/]+/[^/]+/([^%?]+)%?[^"]+"></data>')] = true
      end
      if string.match(html, '<div%s+class="well%s+cover"%s+style="background%-image:%s*url%(https?://[^%.]+%.cloudfront%.net/[^/]+/[^/]+/[^%?]+%?[^%)]+%);"></div>') then
        allowed_strings[string.match(html, '<div%s+class="well%s+cover"%s+style="background%-image:%s*url%(https?://[^%.]+%.cloudfront%.net/[^/]+/[^/]+/([^%?]+)%?[^%)]+%);"></div>')] = true
      end
    end

    if string.match(html, 'data%-before%-id="[0-9]+"') then
      check(string.match(url, "^(https?://[^/]+/[^%?]+)") .. "?before_id=" .. string.match(html, 'data%-before%-id="([0-9]+)"'))
    end

    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      check(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]

  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. ".  \n")
  io.stdout:flush()

  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404 and status_code ~= 410) or
    status_code == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 1")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end