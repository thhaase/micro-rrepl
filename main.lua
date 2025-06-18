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
end

function startR(bp)
    if r_terminal_view ~= nil then
        micro.InfoBar():Message("R session already active")
        return
    end
    
    -- Start tmux session first
    shell.RunCommand("tmux new-session -d -s micro_rrepl 'R --interactive'")
    
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

function findNextExecutableLine(buf, start_line)
    local total_lines = buf:LinesNum()
    
    -- Search from the line after current position
    for line_num = start_line + 1, total_lines - 1 do
        local line = buf:Line(line_num)
        if line and not line:match("^%s*$") and not line:match("^%s*#") then
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
        -- No selection, send current line (original behavior)
        local current_line = buf:Line(cursor.Y)
        
        -- If current line is empty or whitespace-only, find next executable line
        if not current_line or current_line:match("^%s*$") then
            local next_line_num = findNextExecutableLine(buf, cursor.Y)
            if next_line_num then
                cursor:GotoLoc(buffer.Loc(0, next_line_num))
                current_line = buf:Line(next_line_num)
                micro.InfoBar():Message("Jumped to next executable line")
            else
                micro.InfoBar():Message("No executable lines found below")
                return
            end
        end
        
        -- Send to tmux session
        shell.RunCommand("tmux send-keys -t micro_rrepl '" .. current_line .. "' Enter")
        
        micro.InfoBar():Message("Sent: " .. current_line)
        cursor:Down()
    end
end
