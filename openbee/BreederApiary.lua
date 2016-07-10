--- Second_Fry's openbee module (v1.0.0)
--- Apiary breeder
function BreederProvider(Creator, IBreeder, config, logger, ItemTypes)
  local BreederApiary = Creator(IBreeder)
  function BreederApiary:_init()
    if config.registry.apiarySide ~= nil then
      logger:debug('  Apiary: wrapping at' .. config.registry.apiarySide .. ' side.\n')
      self.peripheral = peripheral.wrap(config.registry.apiarySide)
      return self
    end
    if config.registry.apiaryProbe == true then
      logger:debug('  Apiary: probing for.\n')
      self.peripheral = peripheral.find('tile_for_apiculture_0_name') -- OpenPeripherals #90
      if self.peripheral == nil then
        logger:debug('  Apiary: probing failed.\n')
      else
        logger:debug('  Apiary: probing success.\n')
      end
    end
    if self.peripheral == nil then
      logger:log('  Available peripheral sides: ' .. table.concat(peripheral.getNames(), ', ') .. '.\n')
            :color(colors.yellow)
            :log('< Apiary: side? ')
            :color(colors.white)
      local peripheralSide = io.read()
      self.peripheral = peripheral.wrap(peripheralSide)
      if self.peripheral == nil then
        logger:color(colors.red)
              :log('! Apiary: there is no peripheral at ' .. peripheralSide .. ' side.\n')
        error('User lies.')
      end
      config.registry.apiarySide = peripheralSide
      return self
    end
  end
  function BreederApiary:clear()
    local items = self.peripheral.getAllStacks(false)
    if (items[1] ~= nil and ItemTypes[items[1].id].isQueen) or
       (items[1] ~= nil and items[2] ~= nil)
    then
      local residentSleeperTime = 0
      logger:log('    Apiary: waiting (just started)')
      while true do
        sleep(6) -- Bee tick is 20 seconds
        residentSleeperTime = residentSleeperTime + 6
        items = self.peripheral.getAllStacks(false)
        if items[1] == nil then break end
        logger:clearLine():log('    Apiary: waiting (' .. residentSleeperTime .. ' seconds)')
      end
      logger:clearLine():log('    Apiary: done waiting (was ' .. residentSleeperTime .. ' seconds)\n')
    end
    for slot = 3, 9 do
      if items[slot] ~= nil then
        if ItemTypes[items[slot].id] ~= nil and ItemTypes[items[slot].id].isBee then
          self.peripheral.pushItem(config.registry.storageDir, slot, 64)
        else
          self.peripheral.pushItem(config.registry.productDir, slot, 64)
        end
      end
    end
  end
  return BreederApiary
end
