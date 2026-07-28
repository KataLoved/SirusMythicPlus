---@class SMPCompat
SMPCompat = setmetatable({}, {__index = _G})

SMPCompat.Is335 = (select(4, GetBuildInfo()) == 30300)
