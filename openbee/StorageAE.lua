--- Second_Fry's openbee module (v1.0.0)
--- AE2 storage
function StorageProvider(Creator, IStorage, config, logger, ItemTypes)
  local StorageAE = Creator(IStorage)
  function StorageAE:_init()
    if config.registry.AE2MEInterfaceSide ~= nil then
      logger:debug('  AE2: wrapping at' .. config.registry.AE2MEInterfaceSide .. ' side.\n')
      self.peripheral = peripheral.wrap(config.registry.AE2MEInterfaceSide)
      return self
    end
    if config.registry.AE2MEInterfaceProbe == true then
      logger:debug('  AE2: probing for.\n')
      self.peripheral = peripheral.find('tileinterface')
      if self.peripheral == nil then
        logger:debug('  AE2: probing failed. ME Interface not found.\n')
      else
        logger:debug('  AE2: probing success. ME Interface wrapped.\n')
      end
    end
    if self.peripheral == nil then
      logger:log('  Available peripheral sides: ' .. table.concat(peripheral.getNames(), ', ') .. '.\n')
            :color(colors.yellow)
            :log('< AE2: ME Interface side? ')
            :color(colors.white)
      local peripheralSide = io.read()
      self.peripheral = peripheral.wrap(peripheralSide)
      if self.peripheral == nil then
        logger:color(colors.red)
              :log('! AE2: there is no peripheral at ' .. peripheralSide .. ' side.\n')
        error('User lies.')
      end
      config.registry.AE2MEInterfaceSide = peripheralSide
      return self
    end
  end
  function StorageAE:fetch()
    self.items = self.peripheral.getAvailableItems('all')
    self.bees = {}
    for _, item in ipairs(self.items) do
      if ItemTypes[item.fingerprint.id] ~= nil and ItemTypes[item.fingerprint.id].isBee == true then
        self.bees[item.fingerprint] = item.item
      end
    end
    return self
  end
  function StorageAE:putBee(id, peripheralSide, amount, slot)
    if not self.peripheral.canExport(peripheralSide) then
      logger:color(colors.red)
            :log('! AE2: ME Interface can\'t export to ' .. peripheralSide .. ' side.')
      error(peripheralSide .. ' side broken?')
    end
    self.peripheral.exportItem(id, peripheralSide, amount, slot)
    return self
  end
  return StorageAE
end
