-- show the name of current playing file
-- press SHIFT+ENTER to call the function

local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'

local M = {}

function M.prompt_msg(msg, ms)
    mp.commandv("show-text", msg, ms)
end


function M.show_filename()
    local current_filename = mp.get_property("filename")
    M.prompt_msg(current_filename, 2000)
end

-- press SHIFT+ENTER to show current file name
function M.bind_shift_enter()
    mp.add_key_binding('SHIFT+ENTER', 'check_file_name', M.show_filename)
end


function M.unbind_shift_enter()
    mp.remove_key_binding('SHIFT+ENTER')
end


-- main function of the file
function M.main() 
    M.bind_shift_enter()
end

mp.register_event("file-loaded", M.main)


