-- scripts/luukstyrethermalsandwear/modScript.lua
-- BeamNG 0.39: native interAero coexists with companion draft (vehicle ext gates convection).
-- HUD Apps still use Angular host; vehicle publishes via guihooks.queueStream + trigger.
log("I", "luukstyrethermalsandwear", "Executing modScript initialization (0.39-compatible)...")

load("luukstyrethermalsandwear")
setExtensionUnloadMode("luukstyrethermalsandwear", "manual")

load("createbrakeductsliders")
setExtensionUnloadMode("createbrakeductsliders", "manual")

load("tyreWestCoastLapTest")
setExtensionUnloadMode("tyreWestCoastLapTest", "manual")
log("I", "luukstyrethermalsandwear", "tyreWestCoastLapTest loaded (RUN_WC_MANUAL_TEL=manual; profile=kingsnake|GT-IV via trigger body)")
