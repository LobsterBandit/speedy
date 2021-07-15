local addonName = ...
Speedy = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
Speedy.DatabaseName = "SpeedyDB"

-- TODO: handle different expansions and max levels
local MAX_LEVEL = 70
-- set true to update /played time on next TIME_PLAYED_MSG event
local calculateLevelTime = false

-- convert integer returned from UnitSex() to description
local genderMap = {
    [1] = "Unknown",
    [2] = "Male",
    [3] = "Female"
}

local SpeedyDB_defaults = {
    global = {
        Characters = {
            ["*"] = {
                Key = nil,
                Realm = nil,
                Name = nil,
                Class = nil,
                Race = nil,
                Gender = nil, -- enum, need map table
                Level = nil,
                PlayedTotal = 0, -- in seconds
                PlayedLevel = 0, -- in seconds
                LastSeen = nil, -- timestamp in seconds
                LevelTimes = {
                    ["*"] = {
                        XP = nil,
                        XPMax = nil,
                        Played = nil, -- in seconds
                        LastUpdated = nil -- timestamp in seconds
                    }
                }
            }
        },
        -- required XP per level
        LevelXPMax = {
            ["*"] = 0
        }
    }
}

------------------------------------
-- Event Handlers
------------------------------------

local function OnPlayerXPUpdate()
    if Speedy.Character.Level == MAX_LEVEL then
        return
    end

    Speedy.Character.LevelTimes[Speedy.Character.Level + 1].XP = UnitXP("player")
    Speedy.Character.LevelTimes[Speedy.Character.Level + 1].XPMax = Speedy:GetCurrentLevelXPMax()
    Speedy.Character.LevelTimes[Speedy.Character.Level + 1].LastUpdated = time()
end

local function OnTimePlayedMsg(_, totalTime, currentLevelTime)
    Speedy:UnregisterEvent("TIME_PLAYED_MSG")

    local char = Speedy.Character
    char.PlayedTotal = totalTime
    char.PlayedLevel = currentLevelTime

    -- if not max level, update played time of progressing level
    if char.Level ~= MAX_LEVEL then
        char.LevelTimes[char.Level + 1].Played = totalTime
        char.LevelTimes[char.Level + 1].LastUpdated = time()
    end

    if calculateLevelTime then
        char.LevelTimes[char.Level].Played = totalTime - currentLevelTime
        char.LevelTimes[char.Level].LastUpdated = time()
        calculateLevelTime = false
    end

    -- update XP values since we just updated time
    OnPlayerXPUpdate()
end

local function OnPlayerLevelUp(_, newLevel)
    Speedy.Character.Level = newLevel

    Speedy:GetCurrentLevelXPMax()

    -- if now max level, don't need these handlers anymore
    if newLevel == MAX_LEVEL then
        Speedy:UnregisterEvent("PLAYER_LEVEL_UP")
        Speedy:UnregisterEvent("PLAYER_XP_UPDATE")
    end

    local completedLevel = Speedy.Character.LevelTimes[Speedy.Character.Level]
    completedLevel.XP = completedLevel.XPMax
    completedLevel.LastUpdated = time()

    -- request /played to finalize the just achieved level's time
    calculateLevelTime = true
    Speedy:RegisterEvent("TIME_PLAYED_MSG", OnTimePlayedMsg)
    RequestTimePlayed()
end

local function OnPlayerLogout()
    if Speedy.Character.Level ~= MAX_LEVEL then
        Speedy.Character.LevelTimes[Speedy.Character.Level + 1].LastUpdated = time()
    end
    Speedy.Character.LastSeen = time()
end

------------------------------------
-- Mixins
------------------------------------

function Speedy:SetCurrentCharacter()
    local account = "Default"
    local realm = GetRealmName()
    local char = UnitName("player")
    local key = format("%s.%s.%s", account, realm, char)

    if self.db.global.Characters[key].Key == nil then
        self.db.global.Characters[key].Key = key
    end

    self.Character = self.db.global.Characters[key]
end

function Speedy:UpdateCharacterMetadata()
    local char = self.Character
    char.Realm = GetRealmName()
    char.Name = UnitName("player")
    char.Class = UnitClass("player")
    char.Race = UnitRace("player")
    char.Gender = genderMap[UnitSex("player")] or genderMap[1]
    char.Level = UnitLevel("player")
    char.LastSeen = time()
end

function Speedy:PrintCharacterMetadata()
    self:Printf("Key >> %s", self.Character.Key)
    self:Printf("Realm >> %s", self.Character.Realm)
    self:Printf("Name >> %s", self.Character.Name)
    self:Printf("Class >> %s", self.Character.Class)
    self:Printf("Race >> %s", self.Character.Race)
    self:Printf("Level >> %s", self.Character.Level)
    self:Printf("LastSeen >> %s", self.Character.LastSeen)
end

function Speedy:GetCurrentLevelXPMax()
    -- db has it, no need to update
    local xpMax = self.db.global.LevelXPMax[self.Character.Level]
    if xpMax == 0 then
        xpMax = UnitXPMax("player")
        self.db.global.LevelXPMax[self.Character.Level] = xpMax
    end

    return xpMax
end

function Speedy:InitLevelTimes()
    local char = self.Character
    local levelTime = char.LevelTimes[char.Level]

    if levelTime.LastUpdated ~= nil then
        return
    end

    if char.Level == 1 then
        levelTime.XP = 0
        levelTime.XPMax = 0
        levelTime.Played = 0
    else
        local maxXP = self.GetCurrentLevelXPMax()
        levelTime.XP = maxXP
        levelTime.XPMax = maxXP

        calculateLevelTime = true
    end
    levelTime.LastUpdated = time()
end

------------------------------------
-- Addon Setup
------------------------------------

function Speedy:OnInitialize()
    self.Version = "v" .. GetAddOnMetadata("Speedy", "Version")
    self.db = LibStub("AceDB-3.0"):New(self.DatabaseName, SpeedyDB_defaults, true)

    self:SetCurrentCharacter()
end

function Speedy:OnEnable()
    self:Printf("|cffff00ff%s|r", self.Version)

    self:UpdateCharacterMetadata()
    self:GetCurrentLevelXPMax()
    self:InitLevelTimes()
    self:PrintCharacterMetadata()

    self:RegisterEvent("PLAYER_LOGOUT", OnPlayerLogout)
    self:RegisterEvent("TIME_PLAYED_MSG", OnTimePlayedMsg)

    -- only need to register if below max level
    if self.Character.Level ~= MAX_LEVEL then
        self:RegisterEvent("PLAYER_LEVEL_UP", OnPlayerLevelUp)
        self:RegisterEvent("PLAYER_XP_UPDATE", OnPlayerXPUpdate)
    end

    -- trigger a TIME_PLAYED_MSG
    RequestTimePlayed()
end

function Speedy:OnDisable()
    -- TODO: keep a running list of event handlers since not all will be registered at all times
    self:UnregisterEvent("PLAYER_LOGOUT")
    self:UnregisterEvent("TIME_PLAYED_MSG")
    self:UnregisterEvent("PLAYER_LEVEL_UP")
    self:UnregisterEvent("PLAYER_XP_UPDATE")
end
