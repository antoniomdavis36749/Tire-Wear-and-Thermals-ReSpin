local M = {}

-- Fast local cache of frequently accessed primitive functions and tables
local abs = math.abs
local max = math.max
local exp = math.exp

--[[
  LEGACY / FALLBACK thermal grip profiles for tyre_data.getGrip() callers only.
  PRIMARY source of truth: vehicle extension profile schema in
    lua/vehicle/extensions/auto/luukstyrethermalsandwear.lua
    (PROFILE_POINTS / SLICK_SPECTRUM_POINTS / STANDALONE_MODIFIERS).

  Keep these tables aligned with that schema's optimalTemp / plateau / coldWidth /
  hotWidth / gripFloor. Do not tune thermals here for gameplay.
]]
local profiles = {
    -- Slicks: match SLICK_SPECTRUM_POINTS cold cliffs (narrower than old w_cold=68)
    slicks          = { t_opt = 84.0,  plateau = 14.0, w_cold = 46.0, w_hot = 46.0, floor = 0.20 },
    supersoft_slick = { t_opt = 78.0,  plateau = 14.0, w_cold = 44.0, w_hot = 44.0, floor = 0.18 },
    soft_slick      = { t_opt = 78.0,  plateau = 14.0, w_cold = 44.0, w_hot = 44.0, floor = 0.18 },
    medium_slick    = { t_opt = 84.0,  plateau = 14.0, w_cold = 46.0, w_hot = 46.0, floor = 0.20 },
    hard_slick      = { t_opt = 90.0,  plateau = 14.0, w_cold = 48.0, w_hot = 48.0, floor = 0.20 },
    endurance_slick = { t_opt = 90.0,  plateau = 15.0, w_cold = 50.0, w_hot = 52.0, floor = 0.22 },
    drag            = { t_opt = 72.0,  plateau = 12.0, w_cold = 62.0, w_hot = 55.0, floor = 0.28 },
    semislick       = { t_opt = 76.0,  plateau = 14.0, w_cold = 52.0, w_hot = 50.0, floor = 0.24 },
    sport_plus      = { t_opt = 76.0,  plateau = 14.0, w_cold = 52.0, w_hot = 50.0, floor = 0.24 },
    supersport      = { t_opt = 76.0,  plateau = 14.0, w_cold = 52.0, w_hot = 50.0, floor = 0.24 },
    sport           = { t_opt = 66.0,  plateau = 18.0, w_cold = 74.0, w_hot = 55.0, floor = 0.34 },
    street          = { t_opt = 60.0,  plateau = 16.0, w_cold = 58.0, w_hot = 55.0, floor = 0.26 },
    standard        = { t_opt = 60.0,  plateau = 16.0, w_cold = 58.0, w_hot = 55.0, floor = 0.26 },
    drift           = { t_opt = 75.0,  plateau = 14.0, w_cold = 65.0, w_hot = 65.0, floor = 0.28 },
    rally           = { t_opt = 68.0,  plateau = 16.0, w_cold = 62.0, w_hot = 55.0, floor = 0.28 },
    winter          = { t_opt = 38.0,  plateau = 16.0, w_cold = 42.0, w_hot = 40.0, floor = 0.28 },
    rain            = { t_opt = 58.0,  plateau = 15.0, w_cold = 62.0, w_hot = 55.0, floor = 0.28 },
    donut           = { t_opt = 60.0,  plateau = 14.0, w_cold = 55.0, w_hot = 45.0, floor = 0.22 },
    paddle          = { t_opt = 48.0,  plateau = 18.0, w_cold = 58.0, w_hot = 50.0, floor = 0.26 },
    allterrain      = { t_opt = 56.0,  plateau = 18.0, w_cold = 58.0, w_hot = 55.0, floor = 0.26 },
    mudterrain      = { t_opt = 52.0,  plateau = 18.0, w_cold = 58.0, w_hot = 50.0, floor = 0.26 },
    crawler         = { t_opt = 48.0,  plateau = 18.0, w_cold = 58.0, w_hot = 48.0, floor = 0.26 },
    vintage         = { t_opt = 58.0,  plateau = 16.0, w_cold = 58.0, w_hot = 55.0, floor = 0.26 }
}

--[[
  Evaluates compound thermal curves.
  Optional 5th arg `overrides` may supply { t_opt, plateau, w_cold, w_hot, floor }
  so callers can pass profile mods without duplicating tables.
]]
local function getGrip(p, temp, compliance, softness, overrides)
    temp = temp or 21 
    compliance = compliance or 0.5
    softness = softness or 0.5
    
    local c = profiles[p]
    if not c then
        if type(p) == "string" then
            local p_lower = string.lower(p)
            if string.find(p_lower, "slick") then
                c = profiles.slicks
            elseif string.find(p_lower, "allterrain") or string.find(p_lower, "utv") or string.find(p_lower, "utility") then
                c = profiles.allterrain
            elseif string.find(p_lower, "vintage") then
                c = profiles.vintage
            elseif string.find(p_lower, "crawler") then
                c = profiles.crawler
            elseif string.find(p_lower, "sport_plus") or string.find(p_lower, "sportplus") then
                c = profiles.sport_plus
            elseif string.find(p_lower, "sport") then
                c = profiles.sport
            else
                c = profiles.street
            end
            
            profiles[p] = c
        else
            c = profiles.street
        end
    end

    local tOpt = (overrides and overrides.t_opt) or (overrides and overrides.optimalTemp) or c.t_opt
    local plateauBase = (overrides and (overrides.plateau or overrides.tempPlateau)) or c.plateau
    local wColdBase = (overrides and (overrides.w_cold or overrides.coldWidth)) or c.w_cold
    local wHotBase = (overrides and (overrides.w_hot or overrides.hotWidth)) or c.w_hot
    local floor = (overrides and (overrides.floor or overrides.gripFloor)) or c.floor
    
    local scaleFactor = 0.8 + 0.4 * softness
    local current_plateau = plateauBase * scaleFactor
    local current_w_cold = wColdBase * scaleFactor * (1.0 + (compliance - 0.5) * 0.15)
    local current_w_hot = wHotBase * scaleFactor
    
    local diff = abs(temp - tOpt)
    local excess = max(0.0, diff - current_plateau)
    local width = (temp < tOpt) and current_w_cold or current_w_hot
    local power = (temp < tOpt) and 1.35 or 2.0
    local decay = exp(-((excess / max(1.0, width)) ^ power))
    
    return floor + (1.0 - floor) * decay
end

M.getGrip = getGrip
M.profiles = profiles

return M
