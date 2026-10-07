if select(2, UnitRace("player")) ~= "Tauren" then return end

local addonName = ...

local BUFF_SPELL_ID = 1299038 
local TAUREN_RACE_ID = 6     

local activeSoundHandle = nil 
local currentTier = 0         
local maxStacks = 0           
local maxIntroSoundPlayed = 0 -- Tracks the highest 1-8 sound played so they don't repeat unnecessarily
local thirtyStackStartTime = nil 
local thirtyStackTotalTime = 0 
local thirtyStackCurrentSessionTime = 0 
local thirtyStackSessionCount = 0 
local runCompleted = false
local startedFromZero = true 

local totalDuration = 0
local sessionStartTime = nil

TaurunDB = TaurunDB or { addonEnabled = true, thirtyStackTotalTime = 0, thirtyStackCount = 0 }

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

-- Complete reset of the addon (via /taurun reset)
local function FullResetAddon()
    StopAllTaurunSounds()
    currentTier = 0
    maxStacks = 0
    maxIntroSoundPlayed = 0 -- Reset intro sounds tracking
    totalDuration = 0
    sessionStartTime = nil
    thirtyStackCurrentSessionTime = 0
    thirtyStackSessionCount = 0
    thirtyStackTotalTime = 0
    thirtyStackStartTime = nil
    runCompleted = false
    startedFromZero = true

    TaurunDB.addonEnabled = true
    TaurunDB.thirtyStackTotalTime = 0
    TaurunDB.thirtyStackCount = 0
end

local function PlaySoundFileSafely(soundFile, stopPrevious)
    if stopPrevious then
        StopAllTaurunSounds()
        local played, handle = PlaySoundFile(soundFile, "Master")
        if played and handle then
            activeSoundHandle = handle
        end
    else
        PlaySoundFile(soundFile, "Master")
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
    
    if msg == "on" or msg == "music on" then
        TaurunDB.addonEnabled = true
        maxIntroSoundPlayed = 0 -- Fresh start for 1-8 sounds when manually turned back on
        PlaySoundFileSafely("Interface\\AddOns\\Taurun\\sounds\\Moo.mp3", false)
        print("|cFF00FF00[Taurun]|r Taurun music ON")
    elseif msg == "off" or msg == "music off" then
        StopAllTaurunSounds()
        TaurunDB.addonEnabled = false
        print("|cFFFF0000[Taurun]|r Taurun music OFF")
    elseif msg == "reset" or msg == "default" then
        FullResetAddon()
        print("|cFF00FF00[Taurun]|r Default: music ON, stack count/duration reset")
    elseif msg == "moo" then
        PlaySoundFileSafely("Interface\\AddOns\\Taurun\\sounds\\Moo.mp3", false)
        DoEmote("MOO")
        print("|cFF00FF00\\__     ```    __/")
        print("|cFF00FF00     \\^(o o)^/|r         |cFF00FF00Moo!|r")
    elseif msg == "info" or msg == "status" then
        local current30Running = 0
        if thirtyStackStartTime then
            current30Running = GetTime() - thirtyStackStartTime
        end
        local final30Current = thirtyStackCurrentSessionTime + current30Running
        local final30Total = thirtyStackTotalTime + current30Running
        
        print("|cFFFFD100~~ \\ ^(o o)^ / ~~ [Taurun Info] ~~ \\ ^(o o)^ / ~~|r")
        print("  Session - Full-Stack Count (0->30): " .. thirtyStackSessionCount)
        print("  Session - 30-Stack Duration: " .. FormatTime(final30Current))
        print("~")
        print("  Total - Full-Stack Count (0->30): " .. (TaurunDB.thirtyStackCount or 0))
        print("  Total - 30-Stack Duration: " .. FormatTime(final30Total))
    else
        print("|cFFFFD100~~ \\ ^(o o)^ / ~~ [Taurun Commands] ~~ \\ ^(o o)^ / ~~|r")
        print("  |cFF00FFFF/taurun info|r - Full-stack count, 30-stack duration")
        print("  |cFF00FFFF/taurun on/off|r - Incoming music: " .. (TaurunDB.addonEnabled and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        print("  |cFF00FFFF/taurun reset|r - Default (music ON, stack count/duration reset)")
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
        TaurunDB.thirtyStackCount = TaurunDB.thirtyStackCount or 0
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
        
        -- If stacks drop to 0
        if stacks == 0 then
            startedFromZero = true

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
            
            StopAllTaurunSounds()
            
            if runCompleted then
                TaurunDB.addonEnabled = false
            end
            
            maxStacks = 0
            currentTier = 0
            runCompleted = false
            return
        end
        
        if not runCompleted and currentTier < 30 then
            if stacks > maxStacks then
                maxStacks = stacks
            end
        end
        
        if stacks < 30 then
            if thirtyStackStartTime then
                local elapsed = GetTime() - thirtyStackStartTime
                thirtyStackTotalTime = thirtyStackTotalTime + elapsed
                thirtyStackCurrentSessionTime = thirtyStackCurrentSessionTime + elapsed
                thirtyStackStartTime = nil
                TaurunDB.thirtyStackTotalTime = thirtyStackTotalTime
            end
        end
        
        -- Sound OFF < 9 stacks (drops tier so it can trigger 9 again)
        if stacks < 9 and currentTier >= 9 then
            StopAllTaurunSounds()
            currentTier = stacks
        end
        
        if stacks == 30 then
            if startedFromZero then
                TaurunDB.thirtyStackCount = (TaurunDB.thirtyStackCount or 0) + 1
                thirtyStackSessionCount = thirtyStackSessionCount + 1
                startedFromZero = false
            end

            if not thirtyStackStartTime then
                thirtyStackStartTime = GetTime()
            end
            
            if currentTier < 30 then
                currentTier = 30
                runCompleted = true
                print("|cFF00FF00\\__     ```    __/")
                print("|cFF00FF00     \\^(o o)^/|r         |cFF00FF00Moo!|r")
                DoEmote("TRAIN")
                PlaySoundFileSafely("Interface\\AddOns\\Taurun\\sounds\\Moo.mp3", false)
            end
        else
            if currentTier == 30 and stacks < 30 then
                currentTier = 29 
            end

            if TaurunDB.addonEnabled then
                if stacks >= 9 and stacks < 30 then
                    -- Replay cruising speed sound if reaching 9 again
                    if currentTier < 9 then
                        currentTier = 9
                        PlaySoundFileSafely("Interface\\AddOns\\Taurun\\sounds\\stack_9.mp3", true)
                    end
                else
                    if stacks >= 1 and stacks <= 8 and stacks > currentTier then
                        -- Only play 1-8 sounds if they haven't been heard yet this run
                        if stacks > maxIntroSoundPlayed then
                            maxIntroSoundPlayed = stacks
                            PlaySoundFileSafely(string.format("Interface\\AddOns\\Taurun\\sounds\\stack_%d.mp3", stacks), true)
                        end
                        currentTier = stacks -- Update tier regardless of sound playing
                    end
                end
            end
        end
    end
end)