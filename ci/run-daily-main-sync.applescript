on run argv
  set syncScript to item 1 of argv
  set repoDir to item 2 of argv
  set stdoutPath to item 3 of argv
  set stderrPath to item 4 of argv
  set commandText to "/bin/bash " & quoted form of syncScript & " " & quoted form of repoDir & " >> " & quoted form of stdoutPath & " 2>> " & quoted form of stderrPath & "; exit"

  tell application "Terminal"
    set syncTab to do script commandText
    repeat while busy of syncTab
      delay 1
    end repeat
    try
      close (window of syncTab)
    end try
  end tell
end run
