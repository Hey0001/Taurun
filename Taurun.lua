local addonName = ...

local BUFF_SPELL_ID = 1299038 
local TAUREN_RACE_ID = 6     

local activeSoundHandle = nil 
local currentTier = 0         
local maxStacks = 0           
local thirtyStackStartTime = nil 
local thirtyStackTotalTime = 0 -- Accumulated or frozen time spent at 30 stacks
local thirtyStackCurrentSessionTime = 0 -- Temps passé à 30 stacks pour la session en cours

local totalDuration = 0
local sessionStartTime = nil

TaurunDB = TaurunDB or { addonEnabled = true, thirtyStackTotalTime = 0 }

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_AURA")

local function IsPlayerTauren()
    local _, _, raceID = UnitRace("player")
    return raceID == TAUREN_RACE_ID
end

local function StopAllTaurunSounds()
    if activeSoundHandle then
        StopSound(activeSoundHandle, 0)
        activeSoundHandle = nil
    end
end

-- Full reset of the addon state (via /taurun off or /taurun reset)
local function ResetAddonState()
    StopAllTaurunSounds()
    currentTier = 0
    maxStacks = 0
    if thirtyStackStartTime then
        local elapsed = GetTime() - thirtyStackStartTime
        thirtyStackTotalTime = thirtyStackTotalTime + elapsed
        thirtyStackCurrentSessionTime = thirtyStackCurrentSessionTime + elapsed
        thirtyStackStartTime = nil
        TaurunDB.thirtyStackTotalTime = thirtyStackTotalTime
    end
    totalDuration = 0
    sessionStartTime = nil
    thirtyStackCurrentSessionTime = 0
end

local function PlaySoundFileSafely(soundFile, stopPrevious)
    if stopPrevious then
        StopAllTaurunSounds()
    end
    local played, handle = PlaySoundFile(soundFile, "Master")
    if played and handle then
        activeSoundHandle = handle
    end
end

-- Helper to format seconds into a readable string (e.g., "1m 15s" or "45s")
local function FormatTime(seconds)
    if not seconds or seconds <= 0 then return "0s" end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    if mins > 0 then
        return string.format("%dm %ds", mins, secs)
    else
        return string.format("%ds", secs)
    end
end

SLASH_TAURUN1 = "/taurun"
SlashCmdList["TAURUN"] = function(msg)
    msg = string.lower(string.trim(msg or ""))
    
    if msg == "on" then
        TaurunDB.addonEnabled = true
        PlaySoundFileSafely("Interface\\AddOns\\Taurun\\sounds\\Moo.mp3", false)
        print("|cFF00FF00[Taurun]|r Taurun music ON")
    elseif msg == "off" then
        if sessionStartTime then
            totalDuration = totalDuration + (GetTime() - sessionStartTime)
            sessionStartTime = nil
        end
        -- If turning off while at 30 stacks, freeze the current 30-stack timer chunk
        if thirtyStackStartTime then
            local elapsed = GetTime() - thirtyStackStartTime
            thirtyStackTotalTime = thirtyStackTotalTime + elapsed
            thirtyStackCurrentSessionTime = thirtyStackCurrentSessionTime + elapsed
            thirtyStackStartTime = nil
        end
        ResetAddonState()
        TaurunDB.addonEnabled = false
        print("|cFFFF0000[Taurun]|r Taurun music OFF")
    elseif msg == "reset" then
        ResetAddonState()
        TaurunDB.addonEnabled = true
        print("|cFF00FF00[Taurun]|r Taurun reset : sounds ON, max stacks 0, current duration 0")
    elseif msg == "duration reset" then
        thirtyStackTotalTime = 0
        thirtyStackCurrentSessionTime = 0
        thirtyStackStartTime = nil
        TaurunDB.thirtyStackTotalTime = 0
        print("|cFF00FF00[Taurun]|r 30-stack total duration has been reset.")
    elseif msg == "moo" then
        PlaySoundFileSafely("Interface\\AddOns\\Taurun\\sounds\\Moo.mp3", false)
        DoEmote("MOO")
        print("|cFF00FF00\\__     ```    __/")
        print("|cFF00FF00     \\^(o o)^/|r        |cFF00FF00Moo!|r")
    elseif msg == "info" or msg == "status" then
        -- Calculate active 30-stack current session duration (running + accumulated in session)
        local current30Running = 0
        if thirtyStackStartTime then
            current30Running = GetTime() - thirtyStackStartTime
        end
        local final30Current = thirtyStackCurrentSessionTime + current30Running

        -- Calculate active 30-stack total duration (running + persistent total)
        local final30Total = thirtyStackTotalTime + current30Running
        
        print("|cFFFFD100~~ \\ ^(o o)^ / ~~ [Taurun Info] ~~ \\ ^(o o)^ / ~~|r")
        print("  Music (incoming): " .. (TaurunDB.addonEnabled and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        print("  Max Stacks: " .. maxStacks)
        print("  30-Stack Current Duration: " .. FormatTime(final30Current))
        print("  30-Stack Total Duration: " .. FormatTime(final30Total))
    else
        print("|cFFFFD100~~ \\ ^(o o)^ / ~~ [Taurun Commands] ~~ \\ ^(o o)^ / ~~|r")
        print("  |cFF00FFFF/taurun info|r - Taurun info : music, max stacks, max duration")
		print("  |cFF00FFFF/taurun on/off|r - Taurun music ON/OFF")
		print("  |cFF00FFFF/taurun reset|r - Reset : music ON, max stacks, current max duration")
        print("  |cFF00FFFF/taurun duration reset|r - Reset : total max duration")
        print("  |cFF00FFFF/taurun moo|r - Moo.")
    end
end

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if not IsPlayerTauren() then
            self:UnregisterAllEvents()
        end
    elseif event == "PLAYER_LOGIN" then
        if TaurunDB.addonEnabled == nil then TaurunDB.addonEnabled = true end
        if TaurunDB.thirtyStackTotalTime then
           thirtyStackTotalTime = TaurunDB.thirtyStackTotalTime
        end
    elseif event == "UNIT_AURA" and arg1 == "player" then
        if not IsPlayerTauren() then return end
        
        local stacks = 0
        for i = 1, 40 do
            local a = C_UnitAuras.GetBuffDataByIndex("player", i)
            if a and a.spellId == BUFF_SPELL_ID then
                stacks = a.applications or 1
                break
            end
        end
        
        if stacks > 0 and not sessionStartTime then
            sessionStartTime = GetTime()
        end
        
        -- If stacks drop to 0: complete reset of stats, max stacks, and 30-stack timer
        if stacks == 0 then
            if sessionStartTime then
                totalDuration = totalDuration + (GetTime() - sessionStartTime)
                sessionStartTime = nil
            end
            
            if thirtyStackStartTime then
                local elapsed = GetTime() - thirtyStackStartTime
                thirtyStackTotalTime = thirtyStackTotalTime + elapsed
                thirtyStackCurrentSessionTime = thirtyStackCurrentSessionTime + elapsed
                thirtyStackStartTime = nil
                TaurunDB.thirtyStackTotalTime = thirtyStackTotalTime
            end
            
            ResetAddonState()
            return
        end
        
        if stacks > maxStacks then
            maxStacks = stacks
        end
        
        -- Manage 30-stack timer based on exact positioning
        if stacks < 30 then
            if thirtyStackStartTime then
                local elapsed = GetTime() - thirtyStackStartTime
                thirtyStackTotalTime = thirtyStackTotalTime + elapsed
                thirtyStackCurrentSessionTime = thirtyStackCurrentSessionTime + elapsed
                thirtyStackStartTime = nil
                TaurunDB.thirtyStackTotalTime = thirtyStackTotalTime
            end
        end
        
        if stacks < 9 and currentTier >= 9 then
            if sessionStartTime then
                totalDuration = totalDuration + (GetTime() - sessionStartTime)
                sessionStartTime = nil
            end
            ResetAddonState()
            currentTier = stacks
            return
        end
        
        if stacks == 30 then
            -- Start the 30-stack timer only if we just entered it
            if not thirtyStackStartTime then
                thirtyStackStartTime = GetTime()
            end
            
            if currentTier < 30 then
                currentTier = 30
                TaurunDB.addonEnabled = false -- Automatic disable at 30 stacks
                print("|cFF00FF00\\__     ```    __/")
                print("|cFF00FF00     \\^(o o)^/|r        |cFF00FF00Moo!|r")
                DoEmote("TRAIN")
                PlaySoundFileSafely("Interface\\AddOns\\Taurun\\sounds\\Moo.mp3", false)
            end
        else
            if currentTier == 30 and stacks < 30 then
                currentTier = 29 -- Reset the tier threshold below 30 to allow re-triggering later
            end

            if TaurunDB.addonEnabled then
                if stacks >= 9 and stacks < 30 then
                    if currentTier < 9 then
                        currentTier = 9
                        PlaySoundFileSafely("Interface\\AddOns\\Taurun\\sounds\\stack_9.mp3", true)
                    end
                else
                    if stacks >= 1 and stacks <= 8 and stacks > currentTier then
                        currentTier = stacks
                        PlaySoundFileSafely(string.format("Interface\\AddOns\\Taurun\\sounds\\stack_%d.mp3", stacks), true)
                    end
                end
            end
        end
    end
end)