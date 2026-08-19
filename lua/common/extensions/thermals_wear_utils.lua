local M = {}

local vehicleMassCache


local function sigmoid(x, k)
    x = x or 0
    k = k or 10
    return 1 / (1 + k ^ (-x))
end


local function lerp(a, b, t)
    a = a or 0
    b = b or 0
    t = t or 0
    return a + (b - a) * t
end


local function getVehWeight() 
    if not vehicleMassCache then
        local totalMass = 0
        if v and v.data and v.data.nodes then
            for _, n in pairs(v.data.nodes) do
                totalMass = totalMass + (n.nodeWeight or 0)
            end
        end

        vehicleMassCache = totalMass > 0 and totalMass or 1500
    end
    return vehicleMassCache
end

M.sigmoid = sigmoid
M.lerp = lerp
M.getVehWeight = getVehWeight

return M
