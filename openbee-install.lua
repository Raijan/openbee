--- Second_Fry's openbee modular fork (v2.0.0)
--- Original code and idea by Forte40 @ GitHub (forked at v2.2.1)

local branch = 'master'
local url = 'https://raw.github.com/secondfry/openbee/' .. branch .. '/'
local files = {'openbee-install.lua', 'openbee.lua', 'matron.lua', 'openbee/BreederApiary.lua', 'openbee/StorageAE.lua' }
local folders = {'openbee'}

term.color(colors.green)
io.write('> Installing openbee\n')
term.color(colors.white)

if not http then error('No access to web') end

term.color(colors.lightBlue)
io.write('  Installing folders\n')
term.color(colors.white)
for _, folder in ipairs(folders) do
  io.write('    ' .. folder .. '\n')
  fs.makeDir(folder)
end

term.color(colors.lightBlue)
io.write('  Installing files\n')
term.color(colors.white)
for _, file in ipairs(files) do
  io.write('    ' .. file .. ': ')
  local dataCurrent = ''
  if fs.exists(file) then
    local file = fs.open(file, "r")
    dataCurrent = file.readAll()
    file.close()
    io.write('updating')
  else
    io.write('installing')
  end

  local request = http.get(url .. file)
  if request.getResponseCode() == 200 then
    local data = request.readAll()
    if data == dataCurrent then
      term.color(colors.gray)
      io.write(' same file\n')
      term.color(colors.white)
    else
      local file = fs.open(file, "w")
      file.write(data)
      file.close()
      term.color(colors.gray)
      io.write(' success\n')
      term.color(colors.white)
    end
  else error('  Bad HTTP response code') end
  os.sleep(0.1)
end

term.color(colors.green)
io.write('> Installation successful\n')
term.color(colors.white)
