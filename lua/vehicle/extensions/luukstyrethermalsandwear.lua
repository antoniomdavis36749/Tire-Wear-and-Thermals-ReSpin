-- Non-auto shim so short-name `extensions.luukstyrethermalsandwear` resolves.
-- Real implementation: lua/vehicle/extensions/auto/luukstyrethermalsandwear.lua
-- Credits: lucky4luuk (original), Zesty_Maple98 (Redux expansion). See CREDITS.md.
-- (auto/ is loaded via loadModulesInDirectory → loadAtRoot(..., ""); short-name
-- lazy-load only searches lua/vehicle/extensions/<name>.lua — not auto/).

local autoPath = 'lua/vehicle/extensions/auto/luukstyrethermalsandwear'
local existing = package.loaded[autoPath]
if type(existing) == 'table' then
  return existing
end
return require(autoPath)
