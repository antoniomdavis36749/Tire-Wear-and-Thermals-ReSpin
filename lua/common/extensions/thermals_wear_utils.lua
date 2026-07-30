-- lua/vehicle/extensions/auto/tyre_utils.lua
local M = {}

local vehicleMassCache -- Local variable to store the calculated mass

-- Safely calculates sigmoid outputs with robust parameter fallback
local function sigmoid(x, k)
    x = x or 0
    k = k or 10
    return 1 / (1 + k ^ (-x)) -- Added parentheses for mathematical clarity
end

-- Safely calculates linear interpolation with robust parameter fallback
local function lerp(a, b, t)
    a = a or 0
    b = b or 0
    t = t or 0
    return a + (b - a) * t
end

-- Safely calculates and returns the vehicle's total initial mass in kilograms (kg)
local function getVehWeight() 
    if not vehicleMassCache then
        local totalMass = 0
        if v and v.data and v.data.nodes then
            for _, n in pairs(v.data.nodes) do
                totalMass = totalMass + (n.nodeWeight or 0)
            end
        end
        -- Fallback to standard car weight of 1500 kg if data is missing
        vehicleMassCache = totalMass > 0 and totalMass or 1500
    end
    return vehicleMassCache
end

M.sigmoid = sigmoid
M.lerp = lerp
M.getVehWeight = getVehWeight

return M