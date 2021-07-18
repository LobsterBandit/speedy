local addonName = ...
Speedy = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
Speedy.DatabaseName = "SpeedyDB"

-- color of console output
local CHAT_COLOR = "ff82bf4c"
-- TODO: handle different expansions and max levels
local MAX_LEVEL = 70
-- set true to update /played time on next TIME_PLAYED_MSG event
local calculateLevelTime = false

-- convert integer returned from UnitSex() to description
local GenderMap = {
    [1] = "Unknown",
    [2] = "Male",
    [3] = "Female"
}

local XPMaxPerLevel = {
    [1] = 400,
    [2] = 900,
    [3] = 1400,
    [4] = 2100,
    [5] = 2800,
    [6] = 3600,
    [7] = 4500,
    [8] = 5400,
    [9] = 6500,
    [10] = 7600,
    [11] = 8700,
    [12] = 9800,
    [13] = 11000,
    [14] = 12300,
    [15] = 13600,
    [16] = 15000,
    [17] = 16400,
    [18] = 17800,
    [19] = 19300,
    [20] = 20800,
    [21] = 22400,
    [22] = 24000,
    [23] = 25500,
    [24] = 27200,
    [25] = 28900,
    [26] = 30500,
    [27] = 32200,
    [28] = 33900,
    [29] = 36300,
    [30] = 38800,
    [31] = 41600,
    [32] = 44600,
    [33] = 48000,
    [34] = 51400,
    [35] = 55000,
    [36] = 58700,
    [37] = 62400,
    [38] = 66200,
    [39] = 70200,
    [40] = 74300,
    [41] = 78500,
    [42] = 82800,
    [43] = 87100,
    [44] = 91600,
    [45] = 96300,
    [46] = 101000,
    [47] = 105800,
    [48] = 110700,
    [49] = 115700,
    [50] = 120900,
    [51] = 126100,
    [52] = 131500,
    [53] = 137000,
    [54] = 142500,
    [55] = 148200,
    [56] = 154000,
    [57] = 159900,
    [58] = 165800,
    [59] = 172000,
    [60] = 494000,
    [61] = 574700,
    [62] = 614400,
    [63] = 650300,
    [64] = 682300,
    [65] = 710200,
    [66] = 734100,
    [67] = 753700,
    [68] = 768900,
    [69] = 779700,
    [70] = 0
}

local SpeedyDB_defaults = {
    global = {
        DBVersion = 1,
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
                        Played = nil, -- in seconds
                        LastUpdated = nil -- timestamp in seconds
                    }
                }
            }
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

    -- if now max level, don't need these handlers anymore
    if newLevel == MAX_LEVEL then
        Speedy:UnregisterEvent("PLAYER_LEVEL_UP")
        Speedy:UnregisterEvent("PLAYER_XP_UPDATE")
    end

    local completedLevel = Speedy.Character.LevelTimes[Speedy.Character.Level]
    completedLevel.XP = XPMaxPerLevel[Speedy.Character.Level - 1]
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
    char.Gender = GenderMap[UnitSex("player")] or GenderMap[1]
    char.Level = UnitLevel("player")
    char.LastSeen = time()
end

function Speedy:PrintCharacterMetadata()
    self:PrintMessage("Key >> %s", self.Character.Key)
    self:PrintMessage("Realm >> %s", self.Character.Realm)
    self:PrintMessage("Name >> %s", self.Character.Name)
    self:PrintMessage("Class >> %s", self.Character.Class)
    self:PrintMessage("Race >> %s", self.Character.Race)
    self:PrintMessage("Gender >> %s", self.Character.Gender)
    self:PrintMessage("Level >> %s", self.Character.Level)
    self:PrintMessage("# Levels Tracked >> %d", #(self.Character.LevelTimes))
    self:PrintMessage("LastSeen >> %s", self.Character.LastSeen)
end

function Speedy:InitLevelTimes()
    local char = self.Character
    local levelTime = char.LevelTimes[char.Level]

    if levelTime.LastUpdated ~= nil then
        return
    end

    if char.Level == 1 then
        levelTime.XP = 0
        levelTime.Played = 0
    else
        levelTime.XP = XPMaxPerLevel[char.Level - 1]
        calculateLevelTime = true
    end
    levelTime.LastUpdated = time()
end

function Speedy:PrintMessage(...)
    self:Print("|c" .. CHAT_COLOR .. format(...) .. "|r")
end

function Speedy:PrintVersion()
    self:PrintMessage("Version %s", self.Version)
end

function Speedy:PrintUsage()
    self:PrintMessage("------------------------------------")
    self:PrintVersion()
    self:Print()
    self:PrintMessage("  /speedy           - print this usage info")
    self:PrintMessage("  /speedy version - print version info")
    self:PrintMessage("  /speedy char     - print character data")
    self:PrintMessage("  /speedy export  - print character data in json")
    self:PrintMessage("------------------------------------")
end

function Speedy:ShowExportString()
    local json = LibStub("json.lua")
    self:PrintMessage(json.encode(self.Character))
end

------------------------------------
-- Slash Commands
------------------------------------

function Speedy:SpeedySlashHandler(input)
    if input == nil then
        self:PrintUsage()
        return
    end

    local command = self:GetArgs(input, 1)

    if command == "version" then
        self:PrintVersion()
        return
    end

    if command == "char" then
        self:PrintCharacterMetadata()
        return
    end

    if command == "export" then
        self:ShowExportString()
        return
    end

    if command ~= nil then
        self:PrintMessage("Unknown command: %s", input)
        self:Print()
    end

    self:PrintUsage()
end

------------------------------------
-- Addon Setup
------------------------------------

function Speedy:OnInitialize()
    self.Version = "v" .. GetAddOnMetadata("Speedy", "Version")
    self.db = LibStub("AceDB-3.0"):New(self.DatabaseName, SpeedyDB_defaults, true)

    self:SetCurrentCharacter()
    self:RegisterChatCommand("speedy", "SpeedySlashHandler")
end

function Speedy:OnEnable()
    self:PrintVersion()

    self:UpdateCharacterMetadata()
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
    self:UnregisterChatCommand("speedy")
end
