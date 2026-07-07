---@class SMPLoader
SMPLoader = {}

local modules = {}

SMPLoader._modules = modules

---@generic T
---@param name `T` @Module name
---@return T|{ private: table } @Module reference
function SMPLoader:CreateModule(name)
    if (not modules[name]) then
        modules[name] = { private = {} }
        return modules[name]
    else
        return modules[name]
    end
end

---@generic T
---@param name `T` @Module name
---@return T|{ private: table } @Module reference
function SMPLoader:ImportModule(name)
    if (not modules[name]) then
        modules[name] = { private = {} }
        return modules[name]
    else
        return modules[name]
    end
end

function SMPLoader:PopulateGlobals()
    for name, module in pairs(modules) do
        _G[name] = module
    end
end
