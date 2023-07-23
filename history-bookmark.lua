local mp = require 'mp'
local mops = require 'mp.options'
local mutils = require 'mp.utils'
local mmsg = require 'mp.msg'

local M = {}

local o = {
    save_period = 30,  -- time interval for saving history
    exclude_dir = {},  -- directories to be excluded
    exclude_proto = {
        'https?://', 'magnet://', 'rtmp://', 'smb://', 'ftp://', 'bd://',
        'dvb://', 'bluray://', 'dvd://', 'tv://', 'dshow://', 'cdda://',
    }                  -- protocols to be excluded
}
mops.read_options(o)

local BOOKMARK_NAME = ".mpv.history"


-- param/env/... checking proess
local CheckPipeline = {}

function any(t, f)
    for _, v in ipairs(t) do
        if f(v) then return true end
    end
    return false
end

function CheckPipeline.is_exclude(url)
    local is_local_file = url:find('^file://') == 1 or not url:find('://')
    local contain = function(x) return url:find(x) == 1 end
    if is_local_file then
        return any(o.exclude_dir, contain)
    else
        return any(o.exclude_proto, contain)
    end
end


---
---Wrapper for mp.commandv().
---
---@param msg string The message to be displayed.
---@param ms number The duration of the message in milliseconds.
---@return nil
local function prompt(msg, ms)
    mp.commandv("show-text", msg, ms)
end


---
---Get season and episode number from the file name.
---
---@param fname string The file name.
---@param ref string The reference file name for the episode number.
---@return number?, number?
local function get_episode_info(fname, ref)
    -- Add custom patterns here.
    local patterns = {
        '[Ss](%d+)[Ee](%d+)',            -- "S01E02"
        'season.+(%d+).+episode.+(%d+)', -- "season 1 episode 2"
    }

    -- Try to match the season and episode number.
    for _, pattern in ipairs(patterns) do
        local season, ep = fname:match(pattern)
        if season and ep then
            return tonumber(season), tonumber(ep)
        end
    end

    -- Try to match the episode number only.
    -- match all possible numbers
    local nums, ref_nums = {}, {}
    for num in fname:gmatch('%d+') do table.insert(nums, tonumber(num)) end
    for num in ref:gmatch('%d+') do table.insert(ref_nums, tonumber(num)) end
    -- for each nums, compare with each ref_nums and store min diff
    local most_likely, min_diff = nil, math.huge
    for _, num in ipairs(nums) do
        for _, ref_num in ipairs(ref_nums) do
            local diff = math.abs(num - ref_num)
            if diff ~= 0 and diff < min_diff then
                most_likely, min_diff = num, diff
            end
        end
    end

    return nil, most_likely
end


-- *****************************************************************************
-- Bookmark logic
-- *****************************************************************************
---
---Bookmark class
---
---@class Bookmark
local Bookmark = {}
Bookmark.__index = Bookmark

---
---Create a new Bookmark object.
---
---@param dir string Directory to save the bookmark file.
---@param name string? Name of the bookmark file.
---@return Bookmark
function Bookmark:new(dir, name)
    local o = {}
    setmetatable(o, self)
    o.dir = dir
    o.name = name or BOOKMARK_NAME
    o.path = mutils.join_path(dir, o.name)
    return o
end

---
---Check if the bookmark file exists.
---
---@return boolean
function Bookmark:exist()
    local file = io.open(self.path, "r")
    if file == nil then
        return false
    end
    file:close()
    return true
end

---
---Get the content of the bookmark file.
---
---@return string?
function Bookmark:read()
    local file = io.open(self.path, "r")
    local record = file:read()
    file:close()
    return record
end

---
---Write the content to the bookmark file.
---
---@param content string The content to be written.
---@return nil
function Bookmark:write(content)
    local file = io.open(self.path, "w")
    file:write(content .. "\n")
    file:close()
end

---
---Delete the bookmark file.
---
---@return nil
function Bookmark:delete()
    os.remove(self.path)
end


-- *****************************************************************************
-- Playlist logic
-- *****************************************************************************
---
---Playlist class
---
---@class Playlist
local Playlist = {}
Playlist.__index = Playlist

---
---Create a new Playlist object.
---
---@param dir string The media directory.
---@param exts string[]? The extensions of the media files.
---@return Playlist
function Playlist:new(dir, exts)
    local o = {}
    setmetatable(o, self)
    o.dir = dir
    o.exts = exts or {}
    o.files = {}
    o.bookmark = Bookmark:new(dir)
    o:scan()
    return o
end

---
---Reload the playlist.
---
---@param dir string The media directory.
---@return nil
function Playlist:reload(dir)
    self.dir = dir
    self.files = {}
    self.bookmark = Bookmark:new(dir)
    self:scan()
end

---
---Scan the media files in the directory.
---
---@return nil
function Playlist:scan()
    local file_list = mutils.readdir(self.dir, 'files')
    table.sort(file_list)
    for _, file in ipairs(file_list) do
        -- get file extension
        local ftype = file:match('%.([^.]+)$')
        mmsg.info('Playlist scaned: ' .. file)
        -- if file type is in the extension list
        if ftype and (#self.exts == 0 or self.exts[ftype]) then
            table.insert(self.files, file)
            mmsg.info('Playlist added: ' .. file)
        end
    end
end

---
---Check if the playlist is empty.
---
---@return boolean
function Playlist:empty()
    return #self.files == 0
end

---
---Restore last watched episode.
---
---@return string? The name of the last watched episode.
function Playlist:restore()
    if not self.bookmark:exist() then
        return nil
    end
    local record = self.bookmark:read()
    -- history record is written in the first line
    local name = record:match('([^\n]+)')
    return name
end


---
---Save the history.
---
---@param name string The name of the last watched episode.
---@return nil
function Playlist:record(name)
    self.bookmark:write(name)
end


-- *****************************************************************************
-- mpv event handlers
-- *****************************************************************************
M.playlist = Playlist:new(mutils.getcwd())

-- record process
function M.record_history()
    local path = mp.get_property('path')
    local dir, fname = mutils.split_path(path)
    M.playlist:reload(dir)
    if M.playlist:empty() then
        mmsg.warn('No media file found in the directory.')
        return
    end
    M.playlist:record(fname)
    mmsg.info('Recorded: ' .. fname)
end

local timeout = 15
function M.resume_count_down()
    timeout = timeout - 1
    mmsg.info('Count down: ' .. timeout)
    -- count down only at the beginning
    if (timeout < 1) then
        M.unbind_key()
        return
    end

    local jump_file = M.playlist:restore()
    if not jump_file or jump_file == mp.get_property('filename') then
        M.unbind_key()
        return
    end

    local msg = 'Last watched: '
    local season, ep = get_episode_info(jump_file, mp.get_property('filename'))
    if not ep then
        mmsg.warn('Failed to parse the episode number.')
        msg = msg .. jump_file
    elseif not season then
        msg = msg .. 'EP ' .. ep
    else
        msg = msg .. 'S' .. season .. 'E' .. ep
    end

    msg = msg .. " -- continue? " .. timeout .. " [ENTER/n]"
    prompt(msg, 1000)
end

---
---record the file name when video is paused
---
---@param name any
---@param paused any
---@return nil
function M.on_pause(name, paused)
    if paused then
        M.record_timer:stop()
        M.record_history()
    else
        M.record_timer:resume()
    end
end


-- *****************************************************************************
-- mpv key bindings
-- *****************************************************************************
function M.bind_key()
    mp.add_key_binding('ENTER', 'resume_yes', function ()
        local fname = M.playlist:restore()
        local dir = M.playlist.dir
        local path = mutils.join_path(dir, fname)
        mmsg.info('Jumping to ' .. path)
        mp.commandv('loadfile', path)
        M.unbind_key()
        prompt('Resume successfully', 1500)
    end)
    mp.add_key_binding('n', 'resume_not', function()
        M.unbind_key()
        mmsg.info('Stay at the current episode.')
    end)
    mmsg.info('Bound  the keys: \"Enter\", \"n\".')
end

function M.unbind_key()
    mp.remove_key_binding('resume_yes')
    mp.remove_key_binding('resume_not')
    mmsg.info('Unbound the keys: \"Enter\", \"n\".')

    M.record_timer:kill()
    timeout = 0
    mmsg.info('Resume count down stopped.')
end


-- *****************************************************************************
-- register
-- *****************************************************************************
mp.register_event('file-loaded', function ()
    local fpath = mp.get_property('path')
    if CheckPipeline.is_exclude(fpath) then
        mmsg.info('The file is excluded.')
        return
    end
    local dir, _ = mutils.split_path(fpath)
    mmsg.info('Loaded file: ' .. fpath)
    if not dir then return end

    M.record_timer = mp.add_periodic_timer(o.save_period, M.record_history)
    M.resume_timer = mp.add_periodic_timer(1, M.resume_count_down)

    M.bind_key()
    mp.observe_property("pause", "bool", M.on_pause)
    mp.add_hook("on_unload", 50, M.record_history)
end)
