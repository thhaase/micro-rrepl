VERSION = "1.0.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")
local util = import("micro/util")

local r_terminal_view = nil

function init()
    config.MakeCommand("rrepl", startR, config.NoComplete)
    config.MakeCommand("rrepl-stop", stopR, config.NoComplete)
    config.TryBindKey("Ctrl-r", "lua:rrepl.sendLine", false)
    config.MakeCommand("InsertPipe", InsertPipe, config.NoComplete)
    config.TryBindKey("Ctrl-P", "command:InsertPipe", true)
    config.MakeCommand("InsertArrow", InsertArrow, config.NoComplete)
    config.TryBindKey("Alt-#", "command:InsertArrow", true)
end

function InsertPipe(bp)
    local pipe = " |> "
    local buf = bp.Buf
    local cursor = bp.Cursor
    
    -- Create a new Loc from cursor position
    local loc = buffer.Loc(cursor.X, cursor.Y)
    
    -- Insert the pipe operator at cursor position
    buf:Insert(loc, pipe)
end

function InsertArrow(bp)
    local arrow = " <- "
    local buf = bp.Buf
    local cursor = bp.Cursor
    
    -- Create a new Loc from cursor position
    local loc = buffer.Loc(cursor.X, cursor.Y)
    
    -- Insert the pipe operator at cursor position
    buf:Insert(loc, arrow)
end


function startR(bp)
    if r_terminal_view ~= nil then
        micro.InfoBar():Message("R session already active")
        return
    end

    -- Get the directory of the current file
    local file_path = bp.Buf.Path
    local work_dir = ""
    if file_path and file_path ~= "" then
        work_dir = file_path:match("(.*[/\])")
    end

    local tmux_cmd = "tmux new-session -d -s micro_rrepl"
    if work_dir and work_dir ~= "" then
        -- To handle spaces in path, wrap it in quotes
        tmux_cmd = tmux_cmd .. " -c '" .. work_dir .. "'"
    end
    tmux_cmd = tmux_cmd .. " 'R --interactive'"

    -- Start tmux session first
    shell.RunCommand(tmux_cmd)

    -- Create vertical split like filemanager does
    bp:HSplitIndex(buffer.NewBuffer("", "R Terminal"), true)

    -- Save reference to the new terminal view
    r_terminal_view = micro.CurPane()

    -- Set up the terminal view properties
    r_terminal_view.Buf.Type.Scratch = true
    r_terminal_view.Buf.Type.Readonly = true
    r_terminal_view.Buf:SetOptionNative("statusformatl", "R REPL")
    r_terminal_view.Buf:SetOptionNative("statusformatr", "")

    -- Resize to reasonable width
    r_terminal_view:ResizePane(60)

    -- Now run the terminal command to attach to tmux
    r_terminal_view:HandleCommand("term tmux attach -t micro_rrepl; set-option destroy-unattached on")

    -- Switch back to original pane
    bp:NextSplit()

    micro.InfoBar():Message("R REPL started in right pane")
end

function stopR(bp)
    if r_terminal_view == nil then
        micro.InfoBar():Message("No R session active")
        return
    end
    
    -- Kill tmux session
    shell.RunCommand("tmux kill-session -t micro_rrepl")
    
    -- Close the terminal view
    r_terminal_view:Quit()
    r_terminal_view = nil
    
    micro.InfoBar():Message("R session stopped")
end

-- Helper function to check if a line is effectively empty (whitespace or comments only)
function isEmptyOrComment(line)
    if not line then return true end
    -- Check if line is empty, whitespace-only, or comment-only
    return line:match("^%s*$") or line:match("^%s*#")
end

-- Helper function to remove comments from a line (basic implementation)
function removeComments(line)
    if not line then return "" end
    
    local in_string = false
    local string_char = nil
    local result = ""
    
    for i = 1, #line do
        local char = line:sub(i, i)
        
        if not in_string then
            if char == '"' or char == "'" then
                in_string = true
                string_char = char
                result = result .. char
            elseif char == '#' then
                -- Found comment outside string, stop here
                break
            else
                result = result .. char
            end
        else
            result = result .. char
            if char == string_char then
                -- Check if it's escaped
                local escaped = false
                local j = i - 1
                while j > 0 and line:sub(j, j) == '\\' do
                    escaped = not escaped
                    j = j - 1
                end
                if not escaped then
                    in_string = false
                    string_char = nil
                end
            end
        end
    end
    
    return result
end

-- Helper function to count brackets/braces/parens, ignoring those in strings
function countBrackets(line)
    if not line then return 0, 0, 0 end
    
    local parens = 0
    local brackets = 0
    local braces = 0
    local in_string = false
    local string_char = nil
    
    for i = 1, #line do
        local char = line:sub(i, i)
        
        if not in_string then
            if char == '"' or char == "'" then
                in_string = true
                string_char = char
            elseif char == '(' then
                parens = parens + 1
            elseif char == ')' then
                parens = parens - 1
            elseif char == '[' then
                brackets = brackets + 1
            elseif char == ']' then
                brackets = brackets - 1
            elseif char == '{' then
                braces = braces + 1
            elseif char == '}' then
                braces = braces - 1
            end
        else
            if char == string_char then
                -- Check if it's escaped
                local escaped = false
                local j = i - 1
                while j > 0 and line:sub(j, j) == '\\' do
                    escaped = not escaped
                    j = j - 1
                end
                if not escaped then
                    in_string = false
                    string_char = nil
                end
            end
        end
    end
    
    return parens, brackets, braces
end

-- Helper function to check if line has continuation indicators
function hasContinuation(line)
    if not line then return false end
    
    local clean_line = removeComments(line):gsub("%s+$", "") -- Remove trailing whitespace
    
    -- Check for common R continuation patterns
    local continuations = {
        "%%>%%",  -- pipe operator
        "|>",     -- base pipe
        "%%<>%%", -- other pipe variants
        "%+",     -- plus (for ggplot, etc.)
        ",",      -- comma
        ";",      -- semicolon
        "%%in%%", -- %in% operator
        "%%.*%%", -- any other %...% operator at end
        "&&",     -- logical and
        "||",     -- logical or
        "&",      -- bitwise and
        "|",      -- bitwise or
    }
    
    for _, pattern in ipairs(continuations) do
        if clean_line:match(pattern .. "$") then
            return true
        end
    end
    
    return false
end

-- Helper function to check if line starts a multi-line construct
function startsMultiLineConstruct(line)
    if not line then return false end
    
    local clean_line = removeComments(line):gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Check for R keywords that often start multi-line constructs
    local keywords = {
        "^function%s*%(", -- function definition
        "^if%s*%(",       -- if statement
        "^for%s*%(",      -- for loop
        "^while%s*%(",    -- while loop
        "^repeat%s*{",    -- repeat loop
        "^tryCatch%s*%(", -- error handling
        "^withCallingHandlers%s*%(", -- error handling
    }
    
    for _, pattern in ipairs(keywords) do
        if clean_line:match(pattern) then
            return true
        end
    end
    
    return false
end

-- Main function to find the complete R expression starting from current line
function findCompleteExpression(buf, start_line)
    local total_lines = buf:LinesNum()
    local lines = {}
    local total_parens = 0
    local total_brackets = 0
    local total_braces = 0
    
    -- Start from the current line
    local line_num = start_line
    
    -- Skip empty lines and comments at the beginning
    while line_num < total_lines and isEmptyOrComment(buf:Line(line_num)) do
        line_num = line_num + 1
    end
    
    if line_num >= total_lines then
        return nil, nil -- No executable content found
    end
    
    local start_line_num = line_num
    local first_line = buf:Line(line_num)
    
    -- If it's a simple single line that doesn't start a multi-line construct
    -- and has no open brackets, return just that line
    local p, b, br = countBrackets(first_line)
    if not startsMultiLineConstruct(first_line) and 
       not hasContinuation(first_line) and 
       p == 0 and b == 0 and br == 0 then
        return {first_line}, start_line_num
    end
    
    -- Otherwise, collect lines until we have a complete expression
    while line_num < total_lines do
        local current_line = buf:Line(line_num)
        
        if not isEmptyOrComment(current_line) then
            table.insert(lines, current_line)
            
            -- Update bracket counts
            local p, b, br = countBrackets(current_line)
            total_parens = total_parens + p
            total_brackets = total_brackets + b
            total_braces = total_braces + br
            
            -- Check if this line has continuation
            local has_cont = hasContinuation(current_line)
            
            -- If all brackets are closed and no continuation, we're done
            if total_parens == 0 and total_brackets == 0 and total_braces == 0 and not has_cont then
                break
            end
        end
        
        line_num = line_num + 1
    end
    
    -- If we have unclosed brackets at the end, still return what we found
    if #lines > 0 then
        return lines, start_line_num
    end
    
    return nil, nil
end

function findNextExecutableLine(buf, start_line)
    local total_lines = buf:LinesNum()
    
    -- Search from the line after current position
    for line_num = start_line + 1, total_lines - 1 do
        local line = buf:Line(line_num)
        if not isEmptyOrComment(line) then
            -- Found a non-empty, non-comment line
            return line_num
        end
    end
    
    return nil -- No executable line found
end

function sendLine(bp)
    local buf = bp.Buf
    local cursor = bp.Cursor
    
    -- Check if there's a selection
    if cursor:HasSelection() then
        -- Get selection boundaries
        local start_loc = cursor.CurSelection[1]
        local end_loc = cursor.CurSelection[2]
        
        -- Ensure start comes before end
        local start_y, start_x = start_loc.Y, start_loc.X
        local end_y, end_x = end_loc.Y, end_loc.X
        
        if start_y > end_y or (start_y == end_y and start_x > end_x) then
            start_y, start_x, end_y, end_x = end_y, end_x, start_y, start_x
        end
        
        local lines = {}
        local line_count = 0
        
        -- Extract selected text line by line
        for line_num = start_y, end_y do
            local line_text = buf:Line(line_num)
            if line_text then
                local start_col = 0
                local end_col = util.CharacterCountInString(line_text)
                
                -- Handle partial line selection
                if line_num == start_y then
                    start_col = start_x
                end
                if line_num == end_y then
                    end_col = end_x
                end
                
                -- Extract the relevant portion of the line
                if start_col < end_col then
                    local line_portion = util.String(line_text):sub(start_col + 1, end_col)
                    -- Only add non-empty lines
                    if not line_portion:match("^%s*$") then
                        table.insert(lines, line_portion)
                        line_count = line_count + 1
                    end
                end
            end
        end
        
        if line_count == 0 then
            micro.InfoBar():Message("No valid lines selected")
            return
        end
        
        -- Send all selected lines
        for _, line in ipairs(lines) do
            shell.RunCommand("tmux send-keys -t micro_rrepl '" .. line .. "' Enter")
        end
        
        micro.InfoBar():Message("Sent " .. line_count .. " selected line(s)")
        
        -- Clear selection
        cursor:ResetSelection()
        
    else
        -- No selection, find and send complete expression
        local current_line = buf:Line(cursor.Y)
        
        -- If current line is empty or whitespace-only, find next executable line
        if isEmptyOrComment(current_line) then
            local next_line_num = findNextExecutableLine(buf, cursor.Y)
            if next_line_num then
                cursor:GotoLoc(buffer.Loc(0, next_line_num))
                micro.InfoBar():Message("Jumped to next executable line")
            else
                micro.InfoBar():Message("No executable lines found below")
                return
            end
        end
        
        -- Find complete expression starting from cursor position
        local expression_lines, start_line_num = findCompleteExpression(buf, cursor.Y)
        
        if not expression_lines or #expression_lines == 0 then
            micro.InfoBar():Message("No complete expression found")
            return
        end
        
        -- Send each line of the expression
        for _, line in ipairs(expression_lines) do
            shell.RunCommand("tmux send-keys -t micro_rrepl '" .. line .. "' Enter")
        end
        
        -- Move cursor to the line after the expression
        local end_line = start_line_num + #expression_lines - 1
        if end_line < buf:LinesNum() - 1 then
            cursor:GotoLoc(buffer.Loc(0, end_line + 1))
        end
        
        if #expression_lines == 1 then
            micro.InfoBar():Message("Sent: " .. expression_lines[1])
        else
            micro.InfoBar():Message("Sent " .. #expression_lines .. " line expression")
        end
    end
end
