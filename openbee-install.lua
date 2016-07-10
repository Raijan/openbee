--- Second_Fry's openbee modular fork (v2.0.0)
--- Original code and idea by Forte40 @ GitHub (forked at v2.2.1)

local branch = 'master'
local url = 'https://raw.github.com/secondfry/openbee/' .. branch .. '/'
local filenames = {'openbee-install.lua', 'openbee.lua', 'matron.lua', 'openbee/BreederApiary.lua', 'openbee/StorageAE.lua' }
local folders = {'openbee'}

term.setTextColor(colors.green)
io.write('> Installing openbee\n')
term.setTextColor(colors.white)

if not http then error('No access to web') end

term.setTextColor(colors.lightBlue)
io.write('  Installing folders\n')
term.setTextColor(colors.white)
for _, folder in ipairs(folders) do
  io.write('    ' .. folder .. '\n')
  fs.makeDir(folder)
end

term.setTextColor(colors.lightBlue)
io.write('  Installing files\n')
term.setTextColor(colors.white)
for _, filename in ipairs(filenames) do
  io.write('    ' .. filename .. ': ')

  local data, dataCurrent = '', ''
  if fs.exists(filename) then
    local file = fs.open(filename, "r")
    dataCurrent = file.readAll()
    file.close()
    io.write('updating')
  else
    io.write('installing')
  end

  local request = http.get(url .. filename)
  if request == nil then error('  Request failed') end
  if request.getResponseCode() == 200 then
    data = request.readAll()

    if data == dataCurrent then
      term.setTextColor(colors.gray)
      io.write(' same file\n')
      term.setTextColor(colors.white)
    else
      -- TODO implement coroutines
      if filename == 'openbee-install.lua' then
        filename = '.' .. filename
      end
      local file = fs.open(filename, "w")
      file.write(data)
      file.close()
      term.setTextColor(colors.gray)
      io.write(' success\n')
      term.setTextColor(colors.white)

      if filename == '.openbee-install.lua' then
        term.setTextColor(colors.yellow)
        io.write('  Install file updated, manual user console inputs required:\nmove .openbee-install.lua openbee-install.lua\nopenbee-install.lua\n')
        term.setTextColor(colors.white)
        return
      end
    end
  else error('  Bad HTTP response code') end
  os.sleep(0.1)
end

term.setTextColor(colors.green)
io.write('> Installation successful\n')
term.setTextColor(colors.white)
