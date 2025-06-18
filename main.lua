VERSION = "1.0.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")

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
    r_terminal_view:HandleCommand("term tmux attach -t micro_rrepl")
    
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

function sendLine(bp)
    local line = bp.Buf:Line(bp.Cursor.Y)
    if not line or line:match("^%s*$") then return end
    
    -- Send to tmux session
    shell.RunCommand("tmux send-keys -t micro_rrepl '" .. line .. "' Enter")
    
    micro.InfoBar():Message("Sent: " .. line)
    bp.Cursor:Down()
end
