------ Second_Fry's openbee AE2 fork (v2.0.0)
------ Original idea and code by Forte40 @ GitHub (forked at v2.2.1)
--- Default configuration
--- All sides are used for peripheral.wrap calls. Can be proxied (check OpenPeripheral Proxy).
local configDefault = {
  ['storageProvider'] = 'openbee/StorageAE.lua', -- allows different storage backends
  ['breederProvider'] = 'openbee/BreederApiary.lua', -- allows different breeder backends

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

  -- Old shit, plz remove
  ["apiaryDir"] = "down", -- direction from interface to apiary
  ["interfaceDir"] = "up", -- direction from apiary to interface
  ["productDir"] = "down", -- direction from apiary to throw bee products in
  ["analyzerDir"] = "east", -- direction from AE wrapped peripheral to analyze bees
  ["ignoreSpecies"] = {
    "Leporine"
  },
  ["useAnalyzer"] = true,
  ["useReferenceBees"] = true -- try to keep 1 pure princess and 1 pure drone

}

--- Global variables
local catalog = {} -- catalog is really a catalog. Check catalogBees
catalog.princesses = {}
catalog.princessesBySpecies = {}
catalog.drones = {}
catalog.dronesBySpecies = {}
catalog.queens = {}
catalog.referenceDronesBySpecies = {}
catalog.referencePrincessesBySpecies = {}
catalog.referencePairBySpecies = {}

--- Main program cycle
function main(tArgs)
  -- Header
  term.setTextColor(colors.green)
  log(" > Second_Fry's openbee AE2 fork")
  log(string.format(" (v%d.%d.%d)\n", version.major, version.minor, version.patch))
  logLine(" > Original idea and code by Forte40 @ GitHub")
  term.setTextColor(colors.white)
  -- Argument list
  debug("  Got arguments: ")
  debugTable(tArgs)
  debug("\n")
  -- Priority list result
  debug("  Priority list: ")
  debugTable(traitPriority)
  debug("\n")
  -- Last bits of initialization in local scope
  local interface, apiary = getPeripherals()
  local mutations, beeNames = buildMutationGraph(apiary)
  local scorers = buildScoring()
  debug("  Initial clearing: apiary\n")
  clearApiary(interface, apiary)
  debug("  Initial clearing: analyzer\n")
  clearAnalyzer(interface)
  log("  Initial catalog\n")
  local catalog = catalogBees(interface, scorers)
  if #catalog.queens > 0 then log("  Using all queens\n") end
  while #catalog.queens > 0 do
    breedQueen(interface, apiary, catalog.queens[1])
    catalog = catalogBees(interface, scorers)
  end
  if targetSpecies ~= nil then
    targetSpecies = tArgs[1]:sub(1,1):upper()..tArgs[1]:sub(2):lower()
    if beeNames[targetSpecies] == true then
      breedTargetSpecies(mutations, interface, apiary, scorers, targetSpecies)
    else
      log("  Species "..targetSpecies.." is not found\n")
    end
  else
    while true do
      breedAllSpecies(mutations, interface, apiary, scorers, buildTargetSpeciesList(catalog, apiary))
      catalog = catalogBees(interface, scorers)
    end
  end
end

--- Forte40 code with rewrites
-- utility functions ------------------
function choose(list1, list2)
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

-- fix for some versions returning bees.species.*
local nameFix = {}
function fixName(name)
  if type(name) == "table" then
    name = name.name
  end
  local newName = name:gsub("bees%.species%.",""):gsub("^.", string.upper)
  if name ~= newName then
    nameFix[newName] = name
  end
  return newName
end

function fixBee(bee)
  if bee.individual ~= nil then
    bee.individual.displayName = fixName(bee.individual.displayName)
    if bee.individual.isAnalyzed then
      bee.individual.active.species.name = fixName(bee.individual.active.species.name)
      bee.individual.inactive.species.name = fixName(bee.individual.inactive.species.name)
    end
  end
  return bee
end

function fixParents(parents)
  parents.allele1 = fixName(parents.allele1)
  parents.allele2 = fixName(parents.allele2)
  if parents.result then
    parents.result = fixName(parents.result)
  end
  return parents
end

function beeName(bee)
  if bee.individual.active then
    return bee.individual.active.species.name:sub(1,3) .. "-" ..
            bee.individual.inactive.species.name:sub(1,3)
  else
    return bee.individual.displayName:sub(1,3)
  end
end

-- mutations and scoring --------------
-- build mutation graph
function buildMutationGraph(apiary)
  local mutations = {}
  local beeNames = {}
  function addMutateTo(parent1, parent2, offspring, chance)
    beeNames[parent1] = true
    beeNames[parent2] = true
    beeNames[offspring] = true
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
    fixParents(parents)
    addMutateTo(parents.allele1, parents.allele2, parents.result, parents.chance)
    addMutateTo(parents.allele2, parents.allele1, parents.result, parents.chance)
  end
  mutations.getBeeParents = function(name)
    return apiary.getBeeParents((nameFix[name] or name))
  end
  return mutations, beeNames
end

function buildTargetSpeciesList(catalog, apiary)
  local targetSpeciesList = {}
  local parentss = apiary.getBeeBreedingData()
  for _, parents in pairs(parentss) do
    local skip = false
    for i, ignoreSpecies in ipairs(config.ignoreSpecies) do
      if parents.result == ignoreSpecies then
        skip = true
        break
      end
    end
    if not skip and
            ( -- skip if reference pair exists
            catalog.referencePrincessesBySpecies[parents.result] == nil or
                    catalog.referenceDronesBySpecies[parents.result] == nil
            ) and
            ( -- princess 1 and drone 2 available
            catalog.princessesBySpecies[parents.allele1] ~= nil and
                    catalog.dronesBySpecies[parents.allele2] ~= nil
            ) or
            ( -- princess 2 and drone 1 available
            catalog.princessesBySpecies[parents.allele2] ~= nil and
                    catalog.dronesBySpecies[parents.allele1] ~= nil
            ) then
      table.insert(targetSpeciesList, parents.result)
    end
  end
  return targetSpeciesList
end

-- percent chance of 2 species turning into a target species
function mutateSpeciesChance(mutations, species1, species2, targetSpecies)
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
function mutateBeeChance(mutations, princess, drone, targetSpecies)
  if princess.individual.isAnalyzed then
    if drone.individual.isAnalyzed then
      return (mutateSpeciesChance(mutations, princess.individual.active.species.name, drone.individual.active.species.name, targetSpecies) / 4
              +mutateSpeciesChance(mutations, princess.individual.inactive.species.name, drone.individual.active.species.name, targetSpecies) / 4
              +mutateSpeciesChance(mutations, princess.individual.active.species.name, drone.individual.inactive.species.name, targetSpecies) / 4
              +mutateSpeciesChance(mutations, princess.individual.inactive.species.name, drone.individual.inactive.species.name, targetSpecies) / 4)
    end
  elseif drone.individual.isAnalyzed then
  else
    return mutateSpeciesChance(princess.individual.displayName, drone.individual.displayName, targetSpecies)
  end
end

function buildScoring()
  function makeNumberScorer(trait, default)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return (bee.individual.active[trait] + bee.individual.inactive[trait]) / 2
      else
        return default
      end
    end
    return scorer
  end

  function makeBooleanScorer(trait)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return ((bee.individual.active[trait] and 1 or 0) + (bee.individual.inactive[trait] and 1 or 0)) / 2
      else
        return 0
      end
    end
    return scorer
  end

  function makeTableScorer(trait, default, lookup)
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

function compareBees(scorers, a, b)
  for _, trait in ipairs(traitPriority) do
    local scorer = scorers[trait]
    if scorer ~= nil then
      local aScore = scorer(a)
      local bScore = scorer(b)
      if aScore ~= bScore then
        return aScore > bScore
      end
    end
  end
  return true
end

function compareMates(a, b)
  for i, trait in ipairs(traitPriority) do
    if a[trait] ~= b[trait] then
      return a[trait] > b[trait]
    end
  end
  return true
end

function betterTraits(scorers, a, b)
  local traits = {}
  for _, trait in ipairs(traitPriority) do
    local scorer = scorers[trait]
    if scorer ~= nil then
      local aScore = scorer(a)
      local bScore = scorer(b)
      if bScore > aScore then
        table.insert(traits, trait)
      end
    end
  end
  return traits
end

-- interaction functions --------------

function clearApiary(interface, apiary)
  local bees = apiary.getAllStacks(false)
  -- wait for queen to die
  if (bees[1] ~= nil and bees[1].raw_name == "item.for.beequeenge")
          or (bees[1] ~= nil and bees[2] ~= nil) then
    log("  Waiting for apiary")
    while true do
      sleep(5)
      bees = apiary.getAllStacks(false)
      if bees[1] == nil then
        break
      end
      log(".")
    end
    log("\n")
  end
  for slot = 3, 9 do
    local bee = bees[slot]
    if bee ~= nil then
      if bee.raw_name == "item.for.beedronege" or bee.raw_name == "item.for.beeprincessge" then
        apiary.pushItem(config.interfaceDir, slot, 64)
      else
        apiary.pushItem(config.productDir, slot, 64)
      end
    end
  end
end

function clearAnalyzer(interface)
  if not config.useAnalyzer then
    return
  end
  for analyzerSlot = 9, 12 do
    if interface.pullItem(config.analyzerDir, analyzerSlot) == 0 then
      break
    end
  end
end

function analyzeBee(interface, item)
  clearAnalyzer(interface)
  logLine("    Analyzing "..item.item.display_name)
  if not interface.canExport(config.analyzerDir) then
    log("  ! Analyzer not found, disabling usage\n")
    config.useAnalyzer = false
  end
  interface.exportItem(item.fingerprint, config.analyzerDir, 64, 3)
  while true do
    if interface.pullItem(config.analyzerDir, 9) > 0 then
      break
    end
    sleep(5)
  end
end

function breedBees(interface, apiary, princess, drone)
  clearApiary(interface, apiary)
  interface.exportItem(princess.fingerprint, config.apiaryDir, 1, 1)
  interface.exportItem(drone.fingerprint, config.apiaryDir, 1, 2)
  clearApiary(interface, apiary)
end

function breedQueen(interface, apiary, queen)
  log("    Breeding "..queen.item.display_name.."\n")
  clearApiary(interface, apiary)
  interface.exportItem(queen.fingerprint, config.apiaryDir, 1, 1)
  clearApiary(interface, apiary)
end





function breedAllSpecies(mutations, interface, apiary, scorers, speciesList)
  if #speciesList == 0 then
    log("Please add more bee species and press [Enter]")
    io.read("*l")
  else
    for i, targetSpecies in ipairs(speciesList) do
      breedTargetSpecies(mutations, interface, apiary, scorers, targetSpecies)
    end
  end
end

function breedTargetSpecies(mutations, interface, apiary, scorers, targetSpecies)
  logLine("  Going for "..targetSpecies)
  local catalog = catalogBees(interface, scorers)
  while true do
    if #catalog.princesses == 0 then
      log("Please add more princesses and press [Enter]")
      io.read("*l")
      catalog = catalogBees(interface, scorers)
    elseif #catalog.drones == 0 and next(catalog.referenceDronesBySpecies) == nil then
      log("Please add more drones and press [Enter]")
      io.read("*l")
      catalog = catalogBees(interface, scorers)
    else
      local mates = selectPair(mutations, scorers, catalog, targetSpecies)
      if mates ~= nil then
        if isPureBred(mates.princess.item, mates.drone.item, targetSpecies) then
          break
        else
          breedBees(interface, apiary, mates.princess, mates.drone)
          catalog = catalogBees(interface, scorers)
        end
      else
        log(string.format("Please add more bee species for %s and press [Enter]"), targetSpecies)
        io.read("*l")
        catalog = catalogBees(interface, scorers)
      end
    end
  end
  log("  "..targetSpecies.." is purebred\n")
end

-- selects best pair for target species
--   or initiates breeding of lower species
function selectPair(mutations, scorers, catalog, targetSpecies)
  logLine("    Targetting "..targetSpecies)
  local baseChance = 0
  if #mutations.getBeeParents(targetSpecies) > 0 then
    local parents = mutations.getBeeParents(targetSpecies)[1]
    baseChance = parents.chance
    for _, s in ipairs(parents.specialConditions) do
      logLine("    ", s)
    end
  end
  local mateCombos = choose(catalog.princesses, catalog.drones)
  local mates = {}
  local haveReference = (catalog.referencePrincessesBySpecies[targetSpecies] ~= nil and
          catalog.referenceDronesBySpecies[targetSpecies] ~= nil)
  for i, v in ipairs(mateCombos) do
    local chance = mutateBeeChance(mutations, v[1].item, v[2].item, targetSpecies) or 0
    if (not haveReference and chance >= baseChance / 2) or
            (haveReference and chance > 25) then
      local newMates = {
        ["princess"] = v[1],
        ["drone"] = v[2],
        ["speciesChance"] = chance
      }
      for trait, scorer in pairs(scorers) do
        newMates[trait] = (scorer(v[1].item) + scorer(v[2].item)) / 2
      end
      table.insert(mates, newMates)
    end
  end
  if #mates > 0 then
    table.sort(mates, compareMates)
    for i = math.min(#mates, 10), 1, -1 do
      local parents = mates[i]
      debug(beeName(parents.princess.item), " ", beeName(parents.drone.item), " ", parents.speciesChance, " ", parents.fertility, " ",
        parents.flowering, " ", parents.nocturnal, " ", parents.tolerantFlyer, " ", parents.caveDwelling, " ",
        parents.lifespan, " ", parents.temperatureTolerance, " ", parents.humidityTolerance)
    end
    return mates[1]
  else
    -- check for reference bees and breed if drone count is 1
    if catalog.referencePrincessesBySpecies[targetSpecies] ~= nil and
            catalog.referenceDronesBySpecies[targetSpecies] ~= nil then
      log("      Breeding extra drone from reference bees\n")
      return {
        ["princess"] = catalog.referencePrincessesBySpecies[targetSpecies],
        ["drone"] = catalog.referenceDronesBySpecies[targetSpecies]
      }
    end
    -- attempt lower tier bee
    local parentss = mutations.getBeeParents(targetSpecies)
    if #parentss > 0 then
      log("      Lower tier\n")
      table.sort(parentss, function(a, b) return a.chance > b.chance end)
      local trySpecies = {}
      for i, parents in ipairs(parentss) do
        fixParents(parents)
        if (catalog.referencePairBySpecies[parents.allele2] == nil        -- no reference bee pair
                or table.getn(catalog.referenceDronesBySpecies[parents.allele2]) < 2 -- no extra reference drone
                or catalog.princessesBySpecies[parents.allele2] == nil)       -- no converted princess
                and trySpecies[parents.allele2] == nil then
          table.insert(trySpecies, parents.allele2)
          trySpecies[parents.allele2] = true
        end
        if (catalog.referencePairBySpecies[parents.allele1] == nil
                or table.getn(catalog.referenceDronesBySpecies[parents.allele1]) < 2
                or catalog.princessesBySpecies[parents.allele1] == nil)
                and trySpecies[parents.allele1] == nil then
          table.insert(trySpecies, parents.allele1)
          trySpecies[parents.allele1] = true
        end
      end
      for _, species in ipairs(trySpecies) do
        local mates = selectPair(mutations, scorers, catalog, species)
        if mates ~= nil then
          return mates
        end
      end
    end
    return nil
  end
end

function isPureBred(bee1, bee2, targetSpecies)
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

--- Catalog block
function catalogBees(interface, scorers)
  -- Clear catalog
  catalog = {}
  catalog.princesses = {}
  catalog.princessesBySpecies = {}
  catalog.drones = {}
  catalog.dronesBySpecies = {}
  catalog.queens = {}
  catalog.referenceDronesBySpecies = {}
  catalog.referencePrincessesBySpecies = {}
  catalog.referencePairBySpecies = {}
  -- Analyze bees
  debug("    Analyzing bees\n")
  if config.useAnalyzer == true then
    local analyzeCount = 0
    local stillAnalyzing = true
    while stillAnalyzing do
      local items = getAllBees(interface)
      local analyzeCountLocal = 0
      for _, item in ipairs(items) do
        if not item.item.individual.isAnalyzed then
          analyzeBee(interface, item)
          analyzeCountLocal = analyzeCountLocal + 1
        end
      end
      if analyzeCountLocal == 0 then stillAnalyzing = false else analyzeCount = analyzeCount + analyzeCountLocal end
    end
    if analyzeCount > 0 then log("    Analyzed "..analyzeCount.." new bees\n") end
  end
  -- Marking references
  debug("    Marking refences\n")
  local items = getAllBees(interface)
  if config.useReferenceBees then
    for _, item in ipairs(items) do
      local species = item.item.individual.active.species.name
      if item.item.raw_name == "item.for.beedronege" then -- drones
        if catalog.referenceDronesBySpecies[species] == nil then
          catalog.referenceDronesBySpecies[species] = {}
        end
        table.insert(catalog.referenceDronesBySpecies[species], item)
      elseif item.item.raw_name == "item.for.beeprincessge" then -- princess
        if catalog.referencePrincessesBySpecies[species] == nil then
          catalog.referencePrincessesBySpecies[species] = {}
        end
        table.insert(catalog.referencePrincessesBySpecies[species], item)
      end
      if catalog.referencePrincessesBySpecies[species] ~= nil and catalog.referenceDronesBySpecies[species] ~= nil then
        catalog.referencePairBySpecies[species] = true
      end
    end
    log("    Have reference for: ")
    for species, _ in pairs(catalog.referencePairBySpecies) do log(species..", ") end
    log("\n")
  end
  -- Creating actual breeding catalog
  for _, item in ipairs(items) do
    local bee = item.item
    local species = item.item.individual.active.species.name
    if bee.raw_name == "item.for.beedronege" and table.getn(catalog.referenceDronesBySpecies[species]) > 1 then
      table.insert(catalog.drones, item)
      addBySpecies(catalog.dronesBySpecies, item)
    elseif bee.raw_name == "item.for.beeprincessge" and table.getn(catalog.referencePrincessesBySpecies[species]) > 1 then
      table.insert(catalog.princesses, item)
      addBySpecies(catalog.princessesBySpecies, item)
    elseif bee.id == 13339 then -- queens
      table.insert(catalog.queens, item)
    end
  end
  log("    Usable "..#catalog.queens.." queens, "..#catalog.princesses.." princesses, "..#catalog.drones.." drones\n")
  return catalog
end
function addBySpecies(beesBySpecies, item)
  local bee = item.item
  if bee.individual.isAnalyzed then
    if beesBySpecies[bee.individual.active.species.name] == nil then
      beesBySpecies[bee.individual.active.species.name] = {}
    end
    table.insert(beesBySpecies[bee.individual.active.species.name], item)
    if bee.individual.inactive.species.name ~= bee.individual.active.species.name then
      if beesBySpecies[bee.individual.inactive.species.name] == nil then
        beesBySpecies[bee.individual.inactive.species.name] = {}
      end
      table.insert(beesBySpecies[bee.individual.inactive.species.name], item)
    end
  else
    if beesBySpecies[bee.individual.displayName] == nil then
      beesBySpecies[bee.individual.displayName] = {}
    end
    table.insert(beesBySpecies[bee.individual.displayName], item)
  end
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
        :color(colors.white)

  fs.makeDir('.openbee')
  self.args = args or {}
  self.storage = self:initStorage()
  self.breeder = self:initBreeder()
  self.traitPriority = config.registry.traitPriority
end
--- Iterates over requested species and traits and setups priorities
function App:parseArgs()
  local priority = 1
  local isTrait = false
  for _, marg in ipairs(self.args) do
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
  return _G[filename]['StorageProvider'](Creator, IStorage, config, logger)()
end
function App:initBreeder()
  local path = config.registry.breederProvider
  local filename = string.sub(path, 9) -- remove openbee/
  os.loadAPI(path)
  return _G[filename]['BreederProvider'](Creator, IStorage, config, logger)()
end

--- Breeder classes interface
IBreeder = Creator()
--- Initalizes breeder
-- Stores wrapped peripheral in peripheral attribute
-- @return IBreeder instance for chaining
function IBreeder:_init()
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
    ['isBee'] = true
  },
  ['Forestry:beePrincessGE'] = {
    ['isBee'] = true
  },
  ['Forestry:beeQueenGE'] = {
    ['isBee'] = true
  },
}

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
application = App(arg)
application:parseArgs()
logger:finish()
