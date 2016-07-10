# Second_Fry's openbee modular fork
Bee Breeding with OpenPeripherals and modular backends.
## Overview
* Modules are loaded via `os.loadAPI()` call.
* Module is Provider class, which on Invocation should return class, which implements either IStorage or IBreeder interface.
* Currently implemented backends:
    * Storage:
        * Applied Energistics 2
    * Breeder:
        * Forestry Apiary

## Contribution
* Minimal interface documentation in `openbee.lua`. You may check existent implementations to see logic behind.
## In-game overview
* By default expects storage peripheral on south of breeder peripheral.
* By default expects Analyzer on west of storage peripheral.
* Configurable via `.openbee/config` file which is created after first run.
* You can edit defaults in openbee directly

## Setup
    pastebin run XxjND24H
## Usage
Command Pattern | Example | Comment
----------------|---------|--------
`openbee` | `openbee` | Breed everything
`openbee [species]` | `openbee Imperial` | Specially breed specified species
`openbee [species] [trait]` | `openbee Imperial nocturnal caweDwelling` | Breed species with priority on traits

## Thanks
* Forte40/openbee
* Forestry
* ComputerCraft
* OpenPeripherals
* Applied Energistics
