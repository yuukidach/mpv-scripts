local mp = require 'mp'
local mops = require 'mp.options'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

local M = {}

local WINDOWS = 'windows'
local LINUX = 'linux'
local MACOSX = 'macosx'

local o = {
    save_period = 30, -- time interval for saving history
    exclude_dir = {}, -- directories to be excluded
    exclude_proto = {
        'https?://', 'magnet://', 'rtmp://', 'smb://', 'ftp://', 'bd://',
        'dvb://', 'bluray://', 'dvd://', 'tv://', 'dshow://', 'cdda://',
    } -- protocols to be excluded
}
mops.read_options(o)

function Set (t)
    local set = {}
    for _, v in pairs(t) do set[v] = true end
    return set
end

function SetUnion (a,b)
    local res = {}
    for k in pairs(a) do res[k] = true end
    for k in pairs(b) do res[k] = true end
    return res
end

function LenSet (s)
    local len = 0
    for _ in pairs(s) do len = len + 1 end
    return len
end

EXTENSIONS_VIDEO = Set {
    '3g2', '3gp', 'avi', 'flv', 'm2ts', 'm4v', 'mj2', 'mkv', 'mov',
    'mp4', 'mpeg', 'mpg', 'ogv', 'rmvb', 'webm', 'wmv', 'y4m'
}

EXTENSIONS_AUDIO = Set {
    'aiff', 'ape', 'au', 'flac', 'm4a', 'mka', 'mp3', 'oga', 'ogg',
    'ogm', 'opus', 'wav', 'wma'
}

EXTENSIONS_IMAGES = Set {
    'avif', 'bmp', 'gif', 'j2k', 'jp2', 'jpeg', 'jpg', 'jxl', 'png',
    'svg', 'tga', 'tif', 'tiff', 'webp'
}

EXTENSIONS = SetUnion(EXTENSIONS_VIDEO, EXTENSIONS_AUDIO)
EXTENSIONS = SetUnion(EXTENSIONS, EXTENSIONS_IMAGES)

-- param/env/... checking proess
local CheckPipeline = {}

local function any(t, f)
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
---Detect current system.
---
---@return string The name of the system.
local function get_system_name()
    return mp.get_property_native("platform", "")
end


---
---Wrapper for mp.commandv().
---
---@param msg string The message to be displayed.
---@param ms number The duration of the message in milliseconds.
---@return nil
local function mpv_show_text(msg, ms)
    mp.commandv("show-text", msg, ms)
end


local function levenshtein(s, t)
    local m, n = #s, #t
    local d = {}
    for i = 0, m do d[i] = {} end
    for i = 0, m do d[i][0] = i end
    for j = 0, n do d[0][j] = j end
    for i = 1, m do
        for j = 1, n do
            d[i][j] = math.min(
                d[i - 1][j] + 1,
                d[i][j - 1] + 1,
                d[i - 1][j - 1] + (s:sub(i, i) == t:sub(j, j) and 0 or 1)
            )
        end
    end
    return d[m][n]
end

local split_string = function(str, sep)
    local fields = {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) fields[#fields + 1] = c end)
    return fields
end

---
---Natural sort comparator. Compares strings by splitting them into text and
---numeric parts, so that "Episode 2" < "Episode 10".
---
---@param a string
---@param b string
---@return boolean
local function natural_sort(a, b)
    local function split(s)
        local parts = {}
        for text, num in s:gmatch("(%D*)(%d*)") do
            if text ~= "" then table.insert(parts, text:lower()) end
            if num ~= "" then table.insert(parts, tonumber(num)) end
        end
        return parts
    end
    local pa, pb = split(a), split(b)
    for i = 1, math.min(#pa, #pb) do
        if type(pa[i]) ~= type(pb[i]) then
            return type(pa[i]) == "number"
        end
        if pa[i] ~= pb[i] then return pa[i] < pb[i] end
    end
    return #pa < #pb
end

---
---Get season and episode number from the file name.
---
---@param fname string The file name.
---@param ref_fname string The reference file names.
---@return number?, number? The season and episode number.
local function get_episode_info(fname, ref_fname)
    -- Add custom patterns here.
    local patterns = {
        '[Ss](%d+)[^%d]+(%d+)',          -- "S01E02", "S1 - 03"
        'season.+(%d+).+episode.+(%d+)', -- "season 1 episode 2"
    }

    -- Try to match the season and episode number.
    for _, pattern in ipairs(patterns) do
        local season, ep = fname:match(pattern)
        if season and ep then
            return tonumber(season), tonumber(ep)
        end
    end

    -- ep numbers are usually the only different part in the file names
    -- so we can find the most likely ep number by comparing the file name
    -- with the reference file names

    -- try to split by space, dot and _
    local fname_parts = split_string(fname, '%s%.%_')
    local ref_parts = split_string(ref_fname, '%s%.%_')
    if #fname_parts ~= #ref_parts then
        msg.warn(string.format('Failed to parse the episode number: %s', fname))
        return nil, nil
    end

    -- zip the two lists and calculate the levenshtein distance
    for i, fname_part in ipairs(fname_parts) do
        local ref_part = ref_parts[i]
        local dist = levenshtein(fname_part, ref_part)
        if dist ~= 0 then
            -- grep the number from the string
            local nums, ref_nums = {}, {}
            for num in fname_part:gmatch('%d+') do table.insert(nums, tonumber(num)) end
            for num in ref_part:gmatch('%d+') do table.insert(ref_nums, tonumber(num)) end
            for j, num in ipairs(nums) do
                if num ~= ref_nums[j] then
                    return nil, num
                end
            end
        end
    end

    return nil, nil
end


local function join_path(a, b)
    local joined_path = utils.join_path(a, b)
    -- fix windows path
    if get_system_name() == WINDOWS then
        joined_path = joined_path:gsub('/', '\\')
    end
    return joined_path
end


---
---makedirs function for Lua.
---
---@param dir string The path to be created.
---@return boolean Whether the path is created successfully.
---@return string? The error message if failed.
local function makedirs(dir)
    local args = {}
    local system = get_system_name()
    if system == WINDOWS then
        args = { 'powershell', '-NoProfile', '-Command', 'mkdir', string.format("\"%s\"", dir) }
    elseif system == LINUX or system == MACOSX then
        args = { 'mkdir', '-p', dir }
    else
        return false, string.format('Unsupported system: %s', system)
    end

    local res = mp.command_native({ name = "subprocess", capture_stdout = true, playback_only = false, args = args })
    if res.status ~= 0 then
        msg.error(string.format('Failed to create directory: %s', dir))
        return false, res.error
    end

    return true, nil
end

local function bit_xor(a, b)
    local p, c = 1, 0
    while a > 0 or b > 0 do
        local ra, rb = a % 2, b % 2
        if ra + rb == 1 then c = c + p end
        a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
    end
    return c
end

local function bit_and(a, b)
    local p, c = 1, 0
    while a > 0 and b > 0 do
        local ra, rb = a % 2, b % 2
        if ra + rb > 1 then c = c + p end
        a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
    end
    return c
end

---
---fnv1a hash, used for path hashing. Since there won't be too many path to be
---hashed, the performance is not a big concern.
---
---@param str string The string to be hashed.
---@return string The hash value.
local function fnv1a_hash(str)
    local FNV_prime = 0x01000193
    local FNV_offset_basis = 0x811C9DC5

    local hash = FNV_offset_basis
    for i = 1, #str do
        hash = bit_xor(hash, str:byte(i))
        hash = bit_and(hash * FNV_prime, 0xFFFFFFFF)
    end

    return string.format('%08x', hash)
end


-- *****************************************************************************
-- Record
-- each playlist correspondings to a record
-- each record is a line in the history file
-- *****************************************************************************

---
---Record class
---
---@class Record
local Record = {}
Record.__index = Record

--- Create a new Record object.
---
---@param dir string The media directory.
---@param fname string The name of the last watched episode.
---@param season_num number? The number of the last watched episode.
---@param episode_num number The number of the last watched episode.
---@return Record
function Record:new(dir, fname, season_num, episode_num)
    local record = {}
    setmetatable(record, self)
    record.dir = dir
    record.fname = fname
    record.season_num = season_num
    record.episode_num = episode_num
    return record
end

setmetatable(Record, {
    __call = function(cls, ...)
        return cls:new(...)
    end
})


-- *****************************************************************************
-- History
-- *****************************************************************************
---
---History class
---
---@class History
local History = {}
History.__index = History

function History:from_outer_dir(dir)
    local history = {}
    setmetatable(history, self)
    history.dir = join_path(dir, 'history')
    return history
end

function History:from_dir(dir)
    local history = {}
    setmetatable(history, self)
    history.dir = dir
    return history
end

---Creat with History(dir)
setmetatable(History, {
    __call = function(cls, ...)
        local self = setmetatable({}, cls)
        self:from_dir(...)
        return self
    end
})

---
---Check if the history file exists.
---
---@return boolean
function History:exist()
    if utils.readdir(self.dir) == nil then
        return false
    end
    return true
end

---
---Make sure the history file exists.
---
---@return nil
function History:make_sure_exists()
    if self:exist() then
        msg.info(string.format('History directory exists: %s', self.dir))
        return
    end

    local ok, err = makedirs(self.dir)
    if not ok then
        msg.error(string.format('Failed to create history directory: %s', err))
    else
        msg.info(string.format('History directory created: %s', self.dir))
    end
end

---
---Get records from the history file, each file only contains one record.
---
---@return Record[]
function History:list()
    local records = {}
    self:make_sure_exists()

    local damaged_files = {}
    -- list all files in the directory
    local file_list = utils.readdir(self.dir, 'files')
    -- read records from each file
    for _, file in ipairs(file_list) do
        local path = join_path(self.dir, file)
        msg.info(string.format('Found history file: %s', path))
        local file = io.open(path, "r")
        if file == nil then
            msg.warn(string.format('history:list -- Failed to open history file: %s', path))
            table.insert(damaged_files, path)
            goto continue
        end
        local content = file:read()
        local status, json = pcall(utils.parse_json, content)
        if not status then
            msg.warn(string.format('Failed to decode history file: %s', path))
            table.insert(damaged_files, path)
        else
            local record = Record(json.dir, json.fname, json.season_num, json.episode_num)
            table.insert(records, record)
        end
        file:close()
        ::continue::
    end

    -- remove damaged files
    for _, path in ipairs(damaged_files) do
        msg.info(string.format('Removing damaged history file: %s', path))
        os.remove(path)
    end

    return records
end

---
---save a record to the history dir.
---
---@param record Record The record to be saved.
---@return boolean
function History:save(record)
    if getmetatable(record) ~= Record then
        msg.warn(string.format('Invalid record: %s', record))
        return false
    end

    self:make_sure_exists()

    local file_name = fnv1a_hash(record.dir)
    -- overwrite the file if it exists
    local path = join_path(self.dir, file_name)
    local file = io.open(path, "w")
    if file == nil then
        msg.warn(string.format('history:save -- Failed to open history file: %s', path))
        return false
    end
    local json_str, error = utils.format_json(record)
    if error ~= nil then
        msg.error(string.format('Failed to encode history file: %s, err: %s', path, error))
        return false
    end

    file:write(json_str)
    file:close()

    msg.info(string.format('History saved to: %s, vedio path: %s', path, record.dir))
    return true
end

---
---load a record from the history dir.
---
---@param dir string The media directory.
---@return Record?
function History:load(dir)
    local file_name = fnv1a_hash(dir)
    local path = join_path(self.dir, file_name)
    msg.info(string.format('Loading history from file: %s of dir: %s', path, dir))
    local file = io.open(path, "r")
    if file == nil then
        msg.warn(string.format('history:load -- Failed to open history file: %s', path))
        return nil
    end
    local content = file:read()
    local status, json = pcall(utils.parse_json, content)
    if not status then
        msg.warn(string.format('Failed to decode history file: %s', path))
        return nil
    end
    local record = Record(json.dir, json.fname, json.season_num, json.episode_num)
    return record
end

---
---delete a record from the history dir.
---
---@param dir string The media directory.
function History:delete(dir)
    local file_name = fnv1a_hash(dir)
    local path = join_path(self.dir, file_name)
    os.remove(path)
end

local function get_history_manager()
    local config_dir = mp.command_native({"expand-path", "~~/"})
    if not config_dir then
        msg.error('Failed to get mpv config directory.')
        return nil
    end
    local history = {}
    setmetatable(history, History)
    history.dir = join_path(config_dir, 'history')
    msg.info(string.format('History directory: %s', history.dir))
    return history
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
    local playlist = {}
    setmetatable(playlist, self)
    playlist.dir = dir
    playlist.exts = exts or EXTENSIONS
    playlist.files = {}
    playlist.history = get_history_manager()

    msg.info('Playlist created in: ' .. dir)

    if playlist.history == nil then
        msg.error('Failed to get history manager.')
        os.exit(1)
    end

    playlist:scan()

    return playlist
end

---
---Reload the playlist.
---
---@param dir string The media directory.
---@return nil
function Playlist:reload(dir)
    self.dir = dir
    self.files = {}
    self:scan()
end

---
---Scan the media files in the directory.
---
---@return nil
function Playlist:scan()
    local file_list = utils.readdir(self.dir, 'files')
    if not file_list then
        msg.warn('Failed to read directory: ' .. self.dir)
        return
    end
    table.sort(file_list, natural_sort)
    for _, file in ipairs(file_list) do
        -- get file extension
        local ftype = file:match('%.([^.]+)$')
        -- if file type is in the extension list
        if ftype and (self.exts[ftype] or LenSet(self.exts) == 0) then
            table.insert(self.files, file)
            msg.info('Playlist added: ' .. file)
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
---@return number? The number of the last watched season.
---@return number? The number of the last watched episode.
function Playlist:restore()
    msg.info('Restoring from dir: ' .. self.dir)
    local record = self.history:load(self.dir)
    if not record then
        return nil, nil, nil
    end
    return record.fname, record.season_num, record.episode_num
end

---
---Save the history.
---
---@param name string The name of the last watched episode.
---@return nil
function Playlist:record(name)
    -- get episode number from the file name
    -- use a different file as reference to avoid comparing with self
    local ref = self.files[1]
    if ref == name and #self.files > 1 then
        ref = self.files[2]
    end
    local season, ep = get_episode_info(name, ref)
    msg.info('Recording: ')
    msg.info(string.format('\tDirectory: %s', self.dir))
    msg.info(string.format('\tName: %s', name))
    msg.info(string.format('\tSeason: %s, Episode: %s', season, ep))
    self.history:save(Record(self.dir, name, season, ep))
end

-- *****************************************************************************
-- mpv event handlers
-- *****************************************************************************
M.playlist = Playlist:new(utils.getcwd())
M.initialized = false

-- record process
function M.record_history()
    local path = mp.get_property('path')
    if not path then return end
    local dir, fname = utils.split_path(path)
    M.playlist:reload(dir)
    if M.playlist:empty() then
        msg.warn('No media file found in the directory: ' .. dir)
        return
    end
    M.playlist:record(fname)
    msg.info('Recorded: ' .. fname)
end

local timeout = 15
local resume_info = nil  -- cached on file load, avoids rescanning every second

function M.resume_count_down()
    timeout = timeout - 1
    msg.info('Count down: ' .. timeout)
    if timeout < 1 or not resume_info then
        M.unbind_key()
        return
    end

    local prompt_text = 'Last watched: '
    if not resume_info.ep then
        prompt_text = 'Jump to the last watched episode?'
    elseif not resume_info.season then
        prompt_text = prompt_text .. 'EP ' .. resume_info.ep
    else
        prompt_text = prompt_text .. 'S' .. resume_info.season .. 'E' .. resume_info.ep
    end

    prompt_text = prompt_text .. " -- continue? " .. timeout .. " [ENTER/n]"
    mpv_show_text(prompt_text, 1000)
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

---
---Clean history files once at startup. Remove records whose directories
---no longer exist.
---
---@return nil
local function cleanup_history()
    local records = M.playlist.history:list()
    for _, record in ipairs(records) do
        if utils.readdir(record.dir) == nil then
            msg.info('Removing history file: ' .. record.dir)
            M.playlist.history:delete(record.dir)
        end
    end
end
cleanup_history()

-- *****************************************************************************
-- mpv key bindings
-- *****************************************************************************
function M.bind_key()
    mp.add_key_binding('ENTER', 'resume_yes', function()
        if not resume_info then return end
        local dir = M.playlist.dir
        local path = join_path(dir, resume_info.fname)
        msg.info('Jumping to ' .. path)
        mp.commandv('loadfile', path)
        M.unbind_key()
        mpv_show_text('Resume successfully', 1500)
    end)
    mp.add_key_binding('n', 'resume_not', function()
        M.unbind_key()
        msg.info('Stay at the current episode.')
    end)
    msg.info('Bound  the keys: \"Enter\", \"n\".')
end

function M.unbind_key()
    mp.remove_key_binding('resume_yes')
    mp.remove_key_binding('resume_not')
    msg.info('Unbound the keys: \"Enter\", \"n\".')

    if M.resume_timer then
        M.resume_timer:kill()
        M.resume_timer = nil
    end
    resume_info = nil
    timeout = 0
    msg.info('Resume count down stopped.')
end

-- *****************************************************************************
-- cleanup helper
-- *****************************************************************************
function M.cleanup()
    if M.record_timer then
        M.record_timer:kill()
        M.record_timer = nil
    end
    if M.resume_timer then
        M.resume_timer:kill()
        M.resume_timer = nil
    end
    mp.remove_key_binding('resume_yes')
    mp.remove_key_binding('resume_not')
    if M.initialized then
        mp.unobserve_property(M.on_pause)
    end
    resume_info = nil
end

-- *****************************************************************************
-- register
-- *****************************************************************************
mp.register_event('file-loaded', function()
    local fpath = mp.get_property('path')
    if CheckPipeline.is_exclude(fpath) then
        msg.info('The file is excluded.')
        return
    end
    local dir, _ = utils.split_path(fpath)
    msg.info('Loaded file: ' .. fpath)
    if not dir then return end

    -- clean up previous file's resources
    M.cleanup()

    -- reset timeout for resume prompt
    timeout = 15

    -- check if there's a resume target
    M.playlist:reload(dir)
    local jump_file, season, ep = M.playlist:restore()
    if jump_file and jump_file ~= mp.get_property('filename') then
        resume_info = { fname = jump_file, season = season, ep = ep }
    end

    M.record_timer = mp.add_periodic_timer(o.save_period, M.record_history)
    M.resume_timer = mp.add_periodic_timer(1, M.resume_count_down)

    M.bind_key()
    mp.observe_property("pause", "bool", M.on_pause)
    M.initialized = true
    mp.add_hook("on_unload", 50, M.record_history)
end)
