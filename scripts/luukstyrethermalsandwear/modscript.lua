-- scripts/luukstyrethermalsandwear/modScript.lua
-- Credits: lucky4luuk (original), Zesty_Maple98 (Redux expansion). See CREDITS.md.
-- BeamNG 0.39: native interAero coexists with companion draft (vehicle ext gates convection).
-- HUD Apps still use Angular host; vehicle publishes via queueStream (0.39+) or trigger fallback.

log("I", "luukstyrethermalsandwear", "Executing modScript initialization (0.39-compatible)...")

load("luukstyrethermalsandwear")
setExtensionUnloadMode("luukstyrethermalsandwear", "manual")

load("createbrakeductsliders")
setExtensionUnloadMode("createbrakeductsliders", "manual")
