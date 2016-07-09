--- Apiary breeder
function BreederProvider(Creator, IBreeder, config, logger)
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
    return BreederApiary
end
