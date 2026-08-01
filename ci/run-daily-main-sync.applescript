on run argv
  set syncScript to item 1 of argv
  set repoDir to item 2 of argv
  set stdoutPath to item 3 of argv
  set stderrPath to item 4 of argv
  set terminalTitle to "AI Server 自动同步"
  set commandText to "/bin/bash " & quoted form of syncScript & " " & quoted form of repoDir & " >> " & quoted form of stdoutPath & " 2>> " & quoted form of stderrPath

  tell application "Terminal"
    set syncTab to missing value

    repeat with terminalWindow in windows
      repeat with terminalTab in tabs of terminalWindow
        if custom title of terminalTab is terminalTitle then
          set syncTab to terminalTab
          exit repeat
        end if
      end repeat
      if syncTab is not missing value then exit repeat
    end repeat

    if syncTab is missing value then
      set syncTab to do script commandText
      set custom title of syncTab to terminalTitle
    else if not busy of syncTab then
      do script commandText in syncTab
    end if
  end tell
end run
