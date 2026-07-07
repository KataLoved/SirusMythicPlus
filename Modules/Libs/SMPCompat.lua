---@class SMPCompat
SMPCompat = setmetatable({}, {__index = _G})

SMPCompat.Is335 = (select(4, GetBuildInfo()) == 30300)

if not C_Timer then
    C_Timer = {}
    C_Timer.After = function(delay, callback)
        local frame = CreateFrame("Frame")
        local elapsed = 0
        frame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= delay then
                self:SetScript("OnUpdate", nil)
                callback()
            end
        end)
    end
    C_Timer.NewTicker = function(delay, callback, iterations)
        local frame = CreateFrame("Frame")
        local elapsed = 0
        local count = 0
        local maxCount = iterations or math.huge
        local ticker = {}
        ticker.Cancel = function(self)
            frame:SetScript("OnUpdate", nil)
        end
        frame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= delay then
                elapsed = elapsed - delay
                count = count + 1
                callback(ticker)
                if count >= maxCount then
                    self:SetScript("OnUpdate", nil)
                end
            end
        end)
        return ticker
    end
end
