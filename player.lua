local path = "songs"
local speakers = table.pack(peripheral.find("speaker"))
local monitor = peripheral.find("monitor") -- исправлено: было пустая строка

if #speakers == 0 then
  print("No speakers found!")
  return
end

local dfpwm = require("cc.audio.dfpwm")
local files = fs.list(path)

local songs = {}
for _, file in ipairs(files) do
  if file:sub(-6) == ".dfpwm" then
    table.insert(songs, file)
  end
end

if #songs == 0 then
  print("No songs in 'songs' folder.")
  return
end

local current = 1
local paused = false
local stopPlayback = false
local page = 1
local pageSize = 5
local status = "Stopped"

local function drawUI(termObj)
  termObj.clear()
  termObj.setCursorPos(1,1)
  local w, h = termObj.getSize()

  local lines = {}
  table.insert(lines, "=== DFPWM Player ===")
  table.insert(lines, "Status: " .. status)
  table.insert(lines, "Current: " .. (songs[current] or "None"))
  table.insert(lines, "Page " .. page .. "/" .. math.ceil(#songs/pageSize))
  table.insert(lines, "---------------------")

  local startIdx = (page-1)*pageSize + 1
  local endIdx = math.min(startIdx+pageSize-1, #songs)
  for i = startIdx, endIdx do
    if i == current then
      table.insert(lines, "-> " .. i .. ". " .. songs[i])
    else
      table.insert(lines, "   " .. i .. ". " .. songs[i])
    end
  end

  table.insert(lines, "---------------------")
  table.insert(lines, "[N] Next  [P] Prev  [Space] Pause/Resume")
  table.insert(lines, "[S] Swap  [Q] Quit  [<] PrevPg  [>] NextPg")
  table.insert(lines, "[1-5] Select on page")

  local totalLines = math.min(h, #lines)
  local startY = math.floor((h - totalLines) / 2) + 1

  for i = 1, totalLines do
    local text = lines[i]
    local x = math.floor((w - #text) / 2) + 1
    termObj.setCursorPos(x, startY + i - 1)
    termObj.write(text)
  end
end

function printUI()
  drawUI(term)
  if monitor then drawUI(monitor) end
end

function playSong(idx)
  local decoder = dfpwm.make_decoder()
  local handle = fs.open(path .. "/" .. songs[idx], "rb")
  if not handle then
    status = "Error open: " .. (songs[idx] or "?")
    printUI()
    return
  end
  status = "Playing"
  printUI()
  while true do
    if stopPlayback then break end
    if paused then
      status = "Paused"
      printUI()
      os.sleep(0.1)
    else
      status = "Playing"
      printUI()
      local chunk = handle.read(16 * 1024)
      if not chunk then break end
      local buffer = decoder(chunk)
      -- Отправляем буфер во все динамики параллельно
      local tasks = {}
      for _, sp in ipairs(speakers) do
        table.insert(tasks, function()
          while not sp.playAudio(buffer) do
            os.pullEvent("speaker_audio_empty")
          end
        end)
      end
      parallel.waitForAll(table.unpack(tasks))
    end
  end
  handle.close()
  status = "Stopped"
  printUI()
end

while true do
  printUI()
  stopPlayback = false
  parallel.waitForAny(
    function()
      playSong(current)
      current = (current % #songs) + 1
    end,
    function()
      while true do
        local event, key = os.pullEvent("key")
        if key == keys.n then
          stopPlayback = true
          current = (current % #songs) + 1
          break
        elseif key == keys.p then
          stopPlayback = true
          current = (current - 2) % #songs + 1
          break
        elseif key == keys.space then
          paused = not paused
          printUI()
        elseif key == keys.s then
          print("Enter two song numbers to swap (global numbers):")
          local a, b = io.read("*n", "*n")
          if a and b and songs[a] and songs[b] then
            songs[a], songs[b] = songs[b], songs[a]
            print("Songs swapped.")
          else
            print("Invalid input.")
          end
        elseif key == keys.q then
          stopPlayback = true
          status = "Quit"
          printUI()
          return
        elseif key == keys.comma then
          if page > 1 then page = page - 1 end
          printUI()
        elseif key == keys.period then
          if page < math.ceil(#songs/pageSize) then page = page + 1 end
          printUI()
        elseif key >= keys.one and key <= keys.five then
          local idx = (page-1)*pageSize + (key - keys.zero)
          if songs[idx] then
            stopPlayback = true
            current = idx
            break
          end
        end
      end
    end
  )
end
