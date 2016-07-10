------ Second_Fry's openbee AE2 fork (v2.0.0)
------ Original idea and code by Forte40 @ GitHub (forked at v2.2.1)
--- Default configuration
--- All sides are used for peripheral.wrap calls. Can be proxied (check OpenPeripheral Proxy).
local configDefault = {
  ['storageProvider'] = 'openbee/StorageAE.lua', -- allows different storage backends
  ['breederProvider'] = 'openbee/BreederApiary.lua', -- allows different breeder backends
  ["analyzerDir"] = "west", -- direction from storage to analyzer
  ["storageDir"] = "south", -- direction from breeder to storage
  ["productDir"] = "down", -- direction from breeder to product storage
  ["breederDir"] = "north", -- direction from storage to breeder

  -- StorageAE block
  ['AE2MEInterfaceProbe'] = true, -- automatic probe for AE2 ME Interface
  -- ['AE2MEInterfaceSide'] = 'north', -- set here to skip probing and setup

  -- BreederApiary block
  ['apiaryProbe'] = true, -- automatic probe for Apiary
  -- ['apiarySide'] = 'north', -- set here to skip probing and setup

  -- Trait priorities block
  -- You probably down want to edit this, just supply them at runtime. Check README.md
  ["traitPriority"] = {
    "speciesChance",
    "speed",
    "fertility",
    "nocturnal",
    "tolerantFlyer",
    "temperatureTolerance",
    "humidityTolerance",
    "caveDwelling",
    "effect",
    "flowering",
    "flowerProvider",
    "territory"
  },

  -- FIXME old stuff, rewrite and remove
  ["ignoreSpecies"] = {
    "Leporine"
  },
  ["useAnalyzer"] = true,
  ["useReferenceBees"] = true -- try to keep 1 pure princess and 1 pure drone
}

--- Forte40 code with rewrites
-- All comments in this block below are original
Forte40 = {}
-- utility functions ------------------
function Forte40.choose(list1, list2)
  local newList = {}
  if list2 then
    for i = 1, #list2 do
      for j = 1, #list1 do
        if list1[j] ~= list2[i] then
          table.insert(newList, {list1[j], list2[i]})
        end
      end
    end
  else
    for i = 1, #list1 do
      for j = i, #list1 do
        if list1[i] ~= list1[j] then
          table.insert(newList, {list1[i], list1[j]})
        end
      end
    end
  end
  return newList
end
Forte40.nameFix = {}
-- fix for some versions returning bees.species.*
function Forte40.fixName(name)
  if type(name) == "table" then
    name = name.name
  end
  local newName = name:gsub("bees%.species%.",""):gsub("^.", string.upper)
  if name ~= newName then
    Forte40.nameFix[newName] = name
  end
  return newName
end
function Forte40.fixBee(bee)
  if bee.individual ~= nil then
    bee.individual.displayName = Forte40.fixName(bee.individual.displayName)
    if bee.individual.isAnalyzed then
      bee.individual.active.species.name = Forte40.fixName(bee.individual.active.species.name)
      bee.individual.inactive.species.name = Forte40.fixName(bee.individual.inactive.species.name)
    end
  end
  return bee
end
function Forte40.fixParents(parents)
  parents.allele1 = Forte40.fixName(parents.allele1)
  parents.allele2 = Forte40.fixName(parents.allele2)
  if parents.result then
    parents.result = Forte40.fixName(parents.result)
  end
  return parents
end
function Forte40.beeName(bee)
  if bee.individual.active then
    return bee.individual.active.species.name:sub(1,3) .. "-" ..
        bee.individual.inactive.species.name:sub(1,3)
  else
    return bee.individual.displayName:sub(1,3)
  end
end
-- mutations and scoring --------------
-- build mutation graph
function Forte40.buildMutationGraph(apiary)
  local mutations = {}
  function Forte40.addMutateTo(parent1, parent2, offspring, chance)
    if mutations[parent1] ~= nil then
      if mutations[parent1].mutateTo[offspring] ~= nil then
        mutations[parent1].mutateTo[offspring][parent2] = chance
      else
        mutations[parent1].mutateTo[offspring] = {[parent2] = chance}
      end
    else
      mutations[parent1] = {
        mutateTo = {[offspring]={[parent2] = chance}}
      }
    end
  end
  for _, parents in pairs(apiary.getBeeBreedingData()) do
    Forte40.fixParents(parents)
    Forte40.addMutateTo(parents.allele1, parents.allele2, parents.result, parents.chance)
    Forte40.addMutateTo(parents.allele2, parents.allele1, parents.result, parents.chance)
  end
  mutations.getBeeParents = function(name)
    return apiary.getBeeParents((Forte40.nameFix[name] or name))
  end
  return mutations
end
function Forte40.buildTargetSpeciesList(catalog, apiary)
  local targetSpeciesList = {}
  local parentss = apiary.peripheral.getBeeBreedingData()
  for _, parents in pairs(parentss) do
    local skip = false
    for i, ignoreSpecies in ipairs(config.registry.ignoreSpecies) do
      if parents.result == ignoreSpecies then
        skip = true
        break
      end
    end
    if not skip and
        (catalog.reference[parents.result] == nil or catalog.reference[parents.result].pair == nil) and  -- skip if reference pair exists
        catalog.reference[parents.allele1] ~= nil and catalog.reference[parents.allele2] ~= nil and
        ((catalog.reference[parents.allele1].princess ~= nil and catalog.reference[parents.allele2].drone ~= nil) or -- princess 1 and drone 2 available
        (catalog.reference[parents.allele2].princess ~= nil and catalog.reference[parents.allele1].drone ~= nil)) -- princess 2 and drone 1 available
    then
      table.insert(targetSpeciesList, parents.result)
    end
  end
  return targetSpeciesList
end
-- percent chance of 2 species turning into a target species
function Forte40.mutateSpeciesChance(mutations, species1, species2, targetSpecies)
  local chance = {}
  if species1 == species2 then
    chance[species1] = 100
  else
    chance[species1] = 50
    chance[species2] = 50
  end
  if mutations[species1] ~= nil then
    for species, mutates in pairs(mutations[species1].mutateTo) do
      local mutateChance = mutates[species2]
      if mutateChance ~= nil then
        chance[species] = mutateChance
        chance[species1] = chance[species1] - mutateChance / 2
        chance[species2] = chance[species2] - mutateChance / 2
      end
    end
  end
  return chance[targetSpecies] or 0.0
end
-- percent chance of 2 bees turning into target species
function Forte40.mutateBeeChance(mutations, princess, drone, targetSpecies)
  if princess.individual.isAnalyzed then
    if drone.individual.isAnalyzed then
      return (Forte40.mutateSpeciesChance(mutations, princess.individual.active.species.name, drone.individual.active.species.name, targetSpecies) / 4
          +Forte40.mutateSpeciesChance(mutations, princess.individual.inactive.species.name, drone.individual.active.species.name, targetSpecies) / 4
          +Forte40.mutateSpeciesChance(mutations, princess.individual.active.species.name, drone.individual.inactive.species.name, targetSpecies) / 4
          +Forte40.mutateSpeciesChance(mutations, princess.individual.inactive.species.name, drone.individual.inactive.species.name, targetSpecies) / 4)
    end
  elseif drone.individual.isAnalyzed then
  else
    return Forte40.mutateSpeciesChance(princess.individual.displayName, drone.individual.displayName, targetSpecies)
  end
end
function Forte40.buildScoring()
  local function makeNumberScorer(trait, default)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return (bee.individual.active[trait] + bee.individual.inactive[trait]) / 2
      else
        return default
      end
    end
    return scorer
  end

  local function makeBooleanScorer(trait)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return ((bee.individual.active[trait] and 1 or 0) + (bee.individual.inactive[trait] and 1 or 0)) / 2
      else
        return 0
      end
    end
    return scorer
  end

  local function makeTableScorer(trait, default, lookup)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return ((lookup[bee.individual.active[trait]] or default) + (lookup[bee.individual.inactive[trait]] or default)) / 2
      else
        return default
      end
    end
    return scorer
  end

  local scoresTolerance = {
    ["None"]   = 0,
    ["Up 1"]   = 1,
    ["Up 2"]   = 2,
    ["Up 3"]   = 3,
    ["Up 4"]   = 4,
    ["Up 5"]   = 5,
    ["Down 1"] = 1,
    ["Down 2"] = 2,
    ["Down 3"] = 3,
    ["Down 4"] = 4,
    ["Down 5"] = 5,
    ["Both 1"] = 2,
    ["Both 2"] = 4,
    ["Both 3"] = 6,
    ["Both 4"] = 8,
    ["Both 5"] = 10
  }

  local scoresFlowerProvider = {
    ["None"] = 5,
    ["Rocks"] = 4,
    ["Flowers"] = 3,
    ["Mushroom"] = 2,
    ["Cacti"] = 1,
    ["Exotic Flowers"] = 0,
    ["Jungle"] = 0
  }

  return {
    ["fertility"] = makeNumberScorer("fertility", 1),
    ["flowering"] = makeNumberScorer("flowering", 1),
    ["speed"] = makeNumberScorer("speed", 1),
    ["lifespan"] = makeNumberScorer("lifespan", 1),
    ["nocturnal"] = makeBooleanScorer("nocturnal"),
    ["tolerantFlyer"] = makeBooleanScorer("tolerantFlyer"),
    ["caveDwelling"] = makeBooleanScorer("caveDwelling"),
    ["effect"] = makeBooleanScorer("effect"),
    ["temperatureTolerance"] = makeTableScorer("temperatureTolerance", 0, scoresTolerance),
    ["humidityTolerance"] = makeTableScorer("humidityTolerance", 0, scoresTolerance),
    ["flowerProvider"] = makeTableScorer("flowerProvider", 0, scoresFlowerProvider),
    ["territory"] = function(bee)
      if bee.individual.isAnalyzed then
        return ((bee.individual.active.territory[1] * bee.individual.active.territory[2] * bee.individual.active.territory[3]) +
            (bee.individual.inactive.territory[1] * bee.individual.inactive.territory[2] * bee.individual.inactive.territory[3])) / 2
      else
        return 0
      end
    end
  }
end
function Forte40.compareMates(a, b)
  for i, trait in ipairs(config.registry.traitPriority) do
    if a[trait] ~= b[trait] then
      return a[trait] > b[trait]
    end
  end
  return true
end
function Forte40.breedAllSpecies(mutations, interface, apiary, scorers, speciesList)
  if #speciesList == 0 then
    logger:log('< Forte40: Please add more bee species and press [Enter]')
    io.read("*l")
  else
    for i, targetSpecies in ipairs(speciesList) do
      Forte40.breedTargetSpecies(mutations, interface, apiary, scorers, targetSpecies)
    end
  end
end
function Forte40.breedBees(interface, apiary, princess, drone)
  apiary:clear()
  interface:putBee(princess.id, config.registry.breederDir, 1, 1)
  interface:putBee(drone.id, config.registry.breederDir, 1, 2)
  apiary:clear()
end
-- selects best pair for target species
--   or initiates breeding of lower species
function Forte40.selectPair(mutations, scorers, catalog, targetSpecies)
  logger:color(colors.gray):log('  Forte40: -> ' .. targetSpecies .. '\n'):color(colors.white)
  local baseChance = 0
  if #mutations.getBeeParents(targetSpecies) > 0 then
    local parents = mutations.getBeeParents(targetSpecies)[1]
    baseChance = parents.chance
    if table.getn(parents.specialConditions) > 0 then
      logger:log('  Forte40: special conditions:\n' .. table.concat(parents.specialConditions, '\n') .. '\n')
    end
  end
  local mateCombos = Forte40.choose(catalog.princesses, catalog.drones)
  local mates = {}
  local haveReference =
    catalog.reference[targetSpecies] ~= nil and
    catalog.reference[targetSpecies].princess ~= nil and
    catalog.reference[targetSpecies].drone ~= nil
  for i, v in ipairs(mateCombos) do
    local chance = Forte40.mutateBeeChance(mutations, v[1], v[2], targetSpecies) or 0
    if (not haveReference and chance >= baseChance / 2) or
            (haveReference and chance > 25) then
      local newMates = {
        ["princess"] = v[1],
        ["drone"] = v[2],
        ["speciesChance"] = chance
      }
      for trait, scorer in pairs(scorers) do
        newMates[trait] = (scorer(v[1]) + scorer(v[2])) / 2
      end
      table.insert(mates, newMates)
    end
  end
  if #mates > 0 then
    table.sort(mates, Forte40.compareMates)
    for i = math.min(#mates, 5), 2, -1 do
      local parents = mates[i]
      logger:debug('  Forte40: ' ..
              Forte40.beeName(parents.princess) .. ' ' ..
              Forte40.beeName(parents.drone) .. ' ' ..
              parents.speciesChance .. ' ' ..
              parents.fertility .. ' ' ..
              parents.flowering .. ' ' ..
              parents.nocturnal .. ' ' ..
              parents.tolerantFlyer .. ' ' ..
              parents.caveDwelling .. ' ' ..
              parents.lifespan .. ' ' ..
              parents.temperatureTolerance .. ' ' ..
              parents.humidityTolerance .. '\n')
    end
    local parents = mates[1]
    logger:log('  Forte40: best combination:\n' ..
            Forte40.beeName(parents.princess) .. ' ' ..
            Forte40.beeName(parents.drone) .. ' ' ..
            parents.speciesChance .. ' ' ..
            parents.fertility .. ' ' ..
            parents.flowering .. ' ' ..
            parents.nocturnal .. ' ' ..
            parents.tolerantFlyer .. ' ' ..
            parents.caveDwelling .. ' ' ..
            parents.lifespan .. ' ' ..
            parents.temperatureTolerance .. ' ' ..
            parents.humidityTolerance .. '\n')
    return mates[1]
  else
    -- check for reference bees and breed if drone count is 1
    if catalog.reference[targetSpecies] ~= nil and
       catalog.reference[targetSpecies].princess ~= nil and
       catalog.reference[targetSpecies].drone ~= nil
    then
      logger:log('  Forte40: Breeding extra drone from reference bees\n')
      return {
        ["princess"] = catalog.referencePrincessesBySpecies[targetSpecies],
        ["drone"] = catalog.referenceDronesBySpecies[targetSpecies]
      }
    end
    -- attempt lower tier bee
    local parentss = mutations.getBeeParents(targetSpecies)
    if #parentss > 0 then
      table.sort(parentss, function(a, b) return a.chance > b.chance end)
      local trySpecies = {}
      for i, parents in ipairs(parentss) do
        Forte40.fixParents(parents)
        if (catalog.reference[parents.allele2] == nil or
            catalog.reference[parents.allele2].pair == nil or -- no reference bee pair
            catalog.reference[parents.allele2].droneCount < 2 or -- no extra reference drone
            catalog.reference[parents.allele2].princess == nil) -- no converted princess
            and trySpecies[parents.allele2] == nil then
          table.insert(trySpecies, parents.allele2)
          trySpecies[parents.allele2] = true
        end
        if (catalog.reference[parents.allele1] == nil or
            catalog.reference[parents.allele1].pair == nil or -- no reference bee pair
            catalog.reference[parents.allele1].droneCount < 2 or -- no extra reference drone
            catalog.reference[parents.allele1].princess == nil) -- no converted princess
            and trySpecies[parents.allele1] == nil then
          table.insert(trySpecies, parents.allele1)
          trySpecies[parents.allele1] = true
        end
      end
      for _, species in ipairs(trySpecies) do
        local mates = Forte40.selectPair(mutations, scorers, catalog, species)
        if mates ~= nil then
          return mates
        end
      end
    end
    return nil
  end
end
function Forte40.isPureBred(bee1, bee2, targetSpecies)
  if bee1.individual.isAnalyzed and bee2.individual.isAnalyzed then
    if bee1.individual.active.species.name == bee1.individual.inactive.species.name and
            bee2.individual.active.species.name == bee2.individual.inactive.species.name and
            bee1.individual.active.species.name == bee2.individual.active.species.name and
            (targetSpecies == nil or bee1.individual.active.species.name == targetSpecies) then
      return true
    end
  elseif bee1.individual.isAnalyzed == false and bee2.individual.isAnalyzed == false then
    if bee1.individual.displayName == bee2.individual.displayName then
      return true
    end
  end
  return false
end
function Forte40.breedTargetSpecies(mutations, inv, apiary, scorers, targetSpecies)
  while true do
    if application.catalog.princessesCount == 0 then
      logger:color(colors.yellow)
            :log('< Forte40: Please add more princesses and press [Enter]')
            :color(colors.white)
      io.read("*l")
      application.catalog:run(application.storage)
    elseif application.catalog.dronesCount == 0 then
      logger:color(colors.yellow)
            :log('< Forte40: Please add more drones and press [Enter]')
            :color(colors.white)
      io.read("*l")
      application.catalog:run(application.storage)
    else
      logger:log('  Forte40: targetting ' .. targetSpecies .. '\n')
      local mates = Forte40.selectPair(mutations, scorers, application.catalog:toForte40(), targetSpecies)
      if mates ~= nil then
        if Forte40.isPureBred(mates.princess, mates.drone, targetSpecies) then
          break
        else
          Forte40.breedBees(inv, apiary, mates.princess, mates.drone)
          application.catalog:run(application.storage)
        end
      else
        logger:color(colors.yellow)
              :log('< Forte40: Please add more bee species for ' .. targetSpecies .. ' and press [Enter]')
              :color(colors.white)
        io.read("*l")
        application.catalog:run(application.storage)
      end
    end
  end
  logger:log('< Forte40: Bees are purebred\n')
end

--- Create table-based classes
-- @author http://lua-users.org/wiki/ObjectOrientationTutorial
function Creator(...)
  -- "cls" is the new class
  local cls, bases = {}, {...}
  -- copy base class contents into the new class
  for i, base in ipairs(bases) do
    for k, v in pairs(base) do
      cls[k] = v
    end
  end
  -- set the class's __index, and start filling an "is_a" table that contains this class and all of its bases
  -- so you can do an "instance of" check using my_instance.is_a[MyClass]
  cls.__index, cls.is_a = cls, {[cls] = true}
  for i, base in ipairs(bases) do
    for c in pairs(base.is_a) do
      cls.is_a[c] = true
    end
    cls.is_a[base] = true
  end
  -- the class's __call metamethod
  setmetatable(cls, {__call = function (c, ...)
    local instance = setmetatable({}, c)
    -- run the init method if it's there
    local init = instance._init
    if init then init(instance, ...) end
    return instance
  end})
  -- return the new class table, that's ready to fill with methods
  return cls
end

--- Application class
-- WOW, many OOP, such API, much methods
local App = Creator()
--- Provides most of initialization
function App:_init(args)
  self.version = '2.0.0'
  logger:color(colors.green)
        :log('> Second_Fry\'s openbee AE2 fork (v' .. self.version .. ')\n')
        :log('> Thanks to Forte40 @ GitHub (forked on v2.2.1)\n')
        :color(colors.gray)
        :log('  Got arguments: ' .. table.concat(args, ', ') .. '\n')
        :color(colors.white)
  fs.makeDir('.openbee')
  self.args = args or {}
  self.storage = self:initStorage()
  self.breeder = self:initBreeder()
  self.traitPriority = config.registry.traitPriority
  self:initMutationGraph()
  self.catalog = Catalog()
end
--- Iterates over requested species and traits and setups priorities
function App:parseArgs()
  local priority = 1
  local isTrait = false
  for _, marg in ipairs(self.args) do
    isTrait = false
    for priorityConfig = 1, #self.traitPriority do
      if marg == self.traitPriority[priorityConfig] then
        isTrait = true
        table.remove(self.traitPriority, priorityConfig)
        table.insert(self.traitPriority, priority, marg)
        priority = priority + 1
        break
      end
    end
    if not isTrait then
      self.speciesRequested = marg
    end
  end
end
function App:initStorage()
  local path = config.registry.storageProvider
  local filename = string.sub(path, 9) -- remove openbee/
  os.loadAPI(path)
  return _G[filename]['StorageProvider'](Creator, IStorage, config, logger, ItemTypes)()
end
function App:initBreeder()
  local path = config.registry.breederProvider
  local filename = string.sub(path, 9) -- remove openbee/
  os.loadAPI(path)
  return _G[filename]['BreederProvider'](Creator, IStorage, config, logger, ItemTypes)()
end
function App:initMutationGraph()
  self.beeGraph = {}
  local beeGraph = self.breeder.peripheral.getBeeBreedingData()
  for _, mutation in ipairs(beeGraph) do
    if self.beeGraph[mutation.result] == nil then self.beeGraph[mutation.result] = {} end
    table.insert(self.beeGraph[mutation.result], mutation)
  end
  for _, species in ipairs(self.breeder.peripheral.listAllSpecies()) do
    BeeTypes[species.name] = true
  end
end
function App:analyzerClear()
  local beeID, beeTest, beeRet
  local residentSleeperTime = 0
  if not config.registry.useAnalyzer then return end
  self.storage:fetch()
  logger:log('    Analyzer: checking')
  while true do
    for slot = 9, 12 do self.storage.peripheral.pullItem(config.registry.analyzerDir, slot) end
    -- Check if Analyzer was operating
    -- This is not a cycle, runs once
    for id, bee in pairs(self.storage.bees) do
      if bee.individual.isAnalyzed then
        beeTest = bee
        beeID = id
      end
      break
    end
    if beeTest == nil then break else
      self.storage:putBee(beeID, config.registry.analyzerDir, 1, 6)
      sleep(1)
      residentSleeperTime = residentSleeperTime + 1
      beeRet = self.storage.peripheral.pullItem(config.registry.analyzerDir, 9)
      if beeRet > 0 then break else
        logger:clearLine():log('    Analyzer: waiting (' .. residentSleeperTime .. ' seconds)')
        sleep(5) -- Analyzer tick is 30 seconds
        residentSleeperTime = residentSleeperTime + 5
      end
    end
  end
  logger:clearLine():log('    Analyzer: done waiting (was ' .. residentSleeperTime .. ' seconds)\n')
end
function App:main()
  local doRestart = false
  logger:color(colors.lightBlue)
        :log('  Initial: clearing breeder\n')
        :color(colors.white)
  self.breeder:clear()
  logger:color(colors.lightBlue)
        :log('  Initial: clearing analyzer\n')
        :color(colors.white)
  self:analyzerClear()
  logger:color(colors.lightBlue)
        :log('  Initial: categorizing bees\n')
        :color(colors.white)
  self.catalog:run(self.storage)
  while self.catalog.queens ~= nil do
    logger:color(colors.lightBlue)
          :log('  Initial: clearing queens\n')
          :color(colors.white)
    for id, bee in pairs(self.catalog.queens) do
      self.storage:putBee(id, config.registry.breederDir)
      self.breeder:clear()
    end
    self.catalog:run(self.storage)
  end
  if self.speciesRequested ~= nil then
    self.speciesTarget = self.speciesRequested:sub(1,1):upper() .. self.speciesRequested:sub(2):lower()
    if BeeTypes[self.speciesTarget] ~= true then
      logger:color(colors.red)
            :log('! Species ' .. self.speciesTarget .. ' is not found!\n')
            :color(colors.white)
      return
    end
    Forte40.breedTargetSpecies(Forte40.buildMutationGraph(self.breeder.peripheral), self.storage, self.breeder, Forte40.buildScoring(), self.speciesTarget)
    -- FIXME use self:breedSpecies(self.speciesTarget)
  else -- FIXME implement self:breedAll()
    local mutations, scorers = Forte40.buildMutationGraph(self.breeder.peripheral), Forte40.buildScoring()
    while true do
      Forte40.breedAllSpecies(mutations, self.storage, self.breeder, scorers, Forte40.buildTargetSpeciesList(self.catalog, self.breeder))
      self.catalog:run(self.storage)
    end
  end
end
function App:analyze(id)
  local beeRet
  local residentSleeperTime = 32
  logger:log('    Analyze: some bee')
  self.storage:putBee(id, config.registry.analyzerDir, 64, 3) -- slot 3 is magic number
  sleep(32) -- Analyzer tick is 30 seconds
  while true do
    beeRet = 0
    for slot = 9, 12 do
      beeRet = beeRet + self.storage.peripheral.pullItem(config.registry.analyzerDir, slot)
    end
    if beeRet > 0 then break else
      logger:clearLine():log('    Analyze: waiting (' .. residentSleeperTime .. ' seconds)')
      sleep(5) -- Analyzer tick is 30 seconds
      residentSleeperTime = residentSleeperTime + 5
    end
  end
  logger:clearLine():log('    Analyze: done waiting (was ' .. residentSleeperTime .. ' seconds)\n')
end
function App:breedSpecies(species)
  logger:color(colors.lightBlue)
        :log('  Breeding: ' .. species .. '\n')
        :color(colors.white)
  while true do
    self.catalog:run(self.storage)
    if self.catalog.princesses == nil then
      logger:color(colors.yellow)
            :log('< Breeding: add more princesses?\n')
            :color(colors.white)
      io.read("*l")
    elseif self.catalog.drones == nil then
      logger:color(colors.yellow)
            :log('< Breeding: add more drones?\n')
            :color(colors.white)
      io.read("*l")
    else
      if self.beeGraph[species] ~= nil then
        self.parentBreedable = true
        -- TODO select parent line which exists (i.e. Common can be produced in tons of ways)
        for _, mutation in ipairs(self.beeGraph[species]) do
          for _, parent in ipairs({mutation.allele1, mutation.allele2}) do
            if self.catalog.reference[parent] == nil or
               self.catalog.reference[parent].drone == nil or
               self.catalog.reference[parent].droneCount < 2
            then
              logger:log('  Breeding: getting parent first\n')
              self:breedSpecies(parent)
            end
          end
        end
      else
        logger:color(colors.red)
              :log('  Breeder: can\'t breed prime species (' .. species .. ')')
              :color(colors.white)
        error('Prime ' .. species .. ' is not found.')
      end
      if table.getn(self.beeGraph[species].specialConditions) > 0 then
        logger:log('  Breeder: special conditions:\n' .. self.beeGraph[species].specialConditions:concat('\n'))
              :color(colors.yellow)
              :log('< Breeder: confirm that conditions met\n')
              :color(colors.white)
      end
      -- FIXME do some actual breeding
      break
    end
  end
  logger:log('  Breeding: untested done.\n')
end

--- Catalog class
Catalog = Creator()
function Catalog:run(storage)
  if config.registry.useAnalyzer == true then
    logger:color(colors.lightBlue)
          :log('  Catalog: analyzing bees\n')
          :color(colors.white)
    self:analyzeBees(storage)
  end
  logger:debug('  Catalog: creating\n')
  self:create(storage)
  logger:color(colors.lightBlue)
        :log('  Catalog: (TODO) building local mutation graph \n')
        :color(colors.white)
  self:buildMutationGraph(storage)
end
function Catalog:analyzeBees(storage)
  local analyzeCount = 0
  storage:fetch()
  for id, bee in pairs(storage.bees) do
    if not bee.individual.isAnalyzed then
      application:analyze(id)
      analyzeCount = analyzeCount + 1
    end
  end
  if analyzeCount > 0 then logger:log('    Catalog: analyzed ' .. analyzeCount .. ' new bees\n') end
end
function Catalog:create(storage)
  self.reference = {}
  self.drones = nil
  self.princesses = nil
  self.queens = nil
  storage:fetch()
  for id, bee in pairs(storage.bees) do
    local species = bee.individual.active.species.name
    if self.reference[species] == nil then self.reference[species] = {} end
    if ItemTypes[bee.id].isDrone then
      if self.reference[species].drone == nil then
        self.reference[species].drone = {}
        self.reference[species].droneCount = 0
      end
      if self.drones == nil then
        self.drones = {}
        self.dronesCount = 0
      end
      self.reference[species].drone[id] = bee
      self.reference[species].droneCount = self.reference[species].droneCount + bee.qty
      self.drones[id] = bee
      self.dronesCount = self.dronesCount + bee.qty
    end
    if ItemTypes[bee.id].isPrincess then
      if self.reference[species].princess == nil then
        self.reference[species].princess = {}
        self.reference[species].princessCount = 0
      end
      if self.princesses == nil then
        self.princesses = {}
        self.princessesCount = 0
      end
      self.reference[species].princess[id] = bee
      self.reference[species].princessCount = self.reference[species].princessCount + bee.qty
      self.princesses[id] = bee
      self.princessesCount = self.princessesCount + bee.qty
    end
    if ItemTypes[bee.id].isQueen then
      if self.queens == nil then self.queens = {} end
      self.queens[id] = bee
    end
    if self.reference[species].drone ~= nil and self.reference[species].princess ~= nil then
      self.reference[species].pair = true
    end
  end
  if table.getn(self.reference) > 0 then
    logger:log('    Catalog: have reference for:\n    ')
    for species, table in pairs(self.reference) do if table.pair == true then logger:log(species, ', ') end end
    logger:log('\n')
  end
end
function Catalog:buildMutationGraph()
  -- TODO implement local mutation graph using available bees
end
function Catalog:toForte40()
  local princessList, droneList = {}, {}
  for id, princess in pairs(self.princesses) do
    local proxy = princess
    proxy.id = id
    table.insert(princessList, proxy)
  end
  for id, drone in pairs(self.drones) do
    local proxy = drone
    proxy.id = id
    table.insert(droneList, proxy)
  end
  return {
    ['princesses'] = princessList,
    ['drones'] = droneList,
    ['reference'] = self.reference
  }
end

--- Breeder classes interface
IBreeder = Creator()
--- Initalizes breeder
-- Stores wrapped peripheral in peripheral attribute
-- @return IBreeder instance for chaining
function IBreeder:_init()
  return self
end
--- Clears the breeder
-- Bees should land into storage system (doesn't matter if analyzed or not)
-- @return IBreeder instance for chaining
function IBreeder:clear()
  return self
end

--- Storage classes interface
IStorage = Creator()
--- Initalizes storage
-- Stores wrapped peripheral in peripheral attribute
-- @return IStorage instance for chaining
function IStorage:_init()
  return self
end
--- Gets all and only bees from storage
-- @return IStorage instance for chaining
function IStorage:fetch()
  return self
end
--- Returns all bess from storage
function IStorage:getBees()
  return IStorage:fetch().bees
end
--- Puts bee somewhere
-- @param id ID for bee
-- @param peripheralSide Side where to push
-- @return IStorage instance for chaining
function IStorage:putBee(id, peripheralSide)
  return self
end

--- Item ids for bees
ItemTypes = {
  ['Forestry:beeDroneGE'] = {
    ['isBee'] = true,
    ['isDrone'] = true
  },
  ['Forestry:beePrincessGE'] = {
    ['isBee'] = true,
    ['isPrincess'] = true
  },
  ['Forestry:beeQueenGE'] = {
    ['isBee'] = true,
    ['isQueen'] = true
  },
}
BeeTypes = {}

--- Configuration class
Config = Creator()
function Config:_init(filename)
  self.file = File(filename)
  self.registry = self.file:read()
  if self.registry == nil then
    self.registry = configDefault
    self.file:write(self.registry)
  end
  return self
end

--- Logging class
Log = Creator()
function Log:_init()
  fs.makeDir('.openbee/logs')
  local loglast = table.remove(natsort(fs.list('.openbee/logs')))
  if loglast == nil then
    self.lognum = 1
  else
    self.lognum = tonumber(string.sub(loglast, 5)) + 1
  end
  self.logname = '.openbee/logs/log-' .. string.format("%03d", self.lognum)
  self.logfile = File(self.logname)
  self.logfile:open('w')
end
function Log:log(...)
  self:debug(arg)
  for _, marg in ipairs(arg) do
    if type(marg) == "table" then
      io.write(table.concat(marg, ' '))
    else
      io.write(marg)
    end
  end
  return self
end
function Log:debug(...)
  for _, marg in ipairs(arg) do
    if type(marg) == "table" then
      self.logfile:append(table.concat(marg, ' '))
    else
      self.logfile:append(marg)
    end
  end
  return self
end
function Log:color(color)
  term.setTextColor(color)
  return self
end
function Log:clearLine()
  local x, y = term.getCursorPos()
  term.clearLine()
  term.setCursorPos(1, y)
  return self
end
function Log:finish()
  self:color(colors.green)
      :log('> Successful finish (' .. self.logname .. ')\n')
  self.logfile:close()
end

--- File class
File = Creator()
function File:_init(filename)
  self.filename = filename
  return self
end
function File:open(mode)
  self.file = fs.open(self.filename, mode)
  return self
end
function File:read()
  self:open('r')
  if self.file ~= nil then
    local data = self.file.readAll()
    self:close()
    return textutils.unserialize(data)
  end
end
function File:write(data)
  self:open('w').file.write(textutils.serialize(data))
  self:close()
end
function File:append(data)
  self.file.write(data)
end
function File:close()
  self.file.close()
end

--- natsort
function natsort(o)
  local function padnum(d) return ("%012d"):format(d) end
  table.sort(o, function(a,b)
    return tostring(a):gsub("%d+",padnum) < tostring(b):gsub("%d+",padnum) end)
  return o
end

logger = Log()
config = Config('.openbee/config')
application = App({...})
application:parseArgs()
application:main()
logger:finish()
