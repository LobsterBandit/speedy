local addonName = ...
Speedy = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
Speedy.DatabaseName = "SpeedyDB"

local LibDeflate = LibStub("LibDeflate")
local AceGUI = LibStub("AceGUI-3.0")
-- database version
local DB_VERSION = 2
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
                XP = nil, -- current level xp
                PlayedTotal = 0, -- in seconds
                PlayedLevel = 0, -- in seconds
                LastSeen = nil, -- timestamp in seconds
                LevelTimes = {
                    ["*"] = {
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
    Speedy.Character.XP = UnitXP("player")
end

local function OnTimePlayedMsg(_, totalTime, currentLevelTime)
    Speedy:UnregisterEvent("TIME_PLAYED_MSG")

    local char = Speedy.Character
    char.PlayedTotal = totalTime
    char.PlayedLevel = currentLevelTime

    -- if not max level, update played time of progressing level
    if char.Level ~= MAX_LEVEL then
        char.LevelTimes[tostring(char.Level + 1)].Played = totalTime
        char.LevelTimes[tostring(char.Level + 1)].LastUpdated = time()
    end

    if calculateLevelTime then
        char.LevelTimes[tostring(char.Level)].Played = totalTime - currentLevelTime
        char.LevelTimes[tostring(char.Level)].LastUpdated = time()
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

    -- request /played to finalize the just achieved level's time
    calculateLevelTime = true
    Speedy:RegisterEvent("TIME_PLAYED_MSG", OnTimePlayedMsg)
    RequestTimePlayed()
end

local function OnPlayerLogout()
    if Speedy.Character.Level ~= MAX_LEVEL then
        Speedy.Character.LevelTimes[tostring(Speedy.Character.Level + 1)].LastUpdated = time()
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
    -- update char.XP
    OnPlayerXPUpdate()
end

function Speedy:PrintCharacterMetadata()
    self:PrintMessage("Key >> %s", self.Character.Key)
    self:PrintMessage("Realm >> %s", self.Character.Realm)
    self:PrintMessage("Name >> %s", self.Character.Name)
    self:PrintMessage("Class >> %s", self.Character.Class)
    self:PrintMessage("Race >> %s", self.Character.Race)
    self:PrintMessage("Gender >> %s", self.Character.Gender)
    self:PrintMessage("Level >> %s", self.Character.Level)
    local numLevels = 0
    for _, _ in pairs(self.Character.LevelTimes) do
        numLevels = numLevels + 1
    end
    self:PrintMessage("# Levels Tracked >> %d", numLevels)
    self:PrintMessage("LastSeen >> %s", self.Character.LastSeen)
end

function Speedy:InitLevelTimes()
    local char = self.Character
    local levelTime = char.LevelTimes[tostring(char.Level)]

    if levelTime.LastUpdated ~= nil then
        return
    end

    if char.Level == 1 then
        levelTime.Played = 0
    else
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
    self:PrintMessage("  /speedy export  - export character data")
    self:PrintMessage("------------------------------------")
end

function Speedy:ShowExportString()
    local json = LibStub("json.lua")
    local data = json.encode(self.db.global.Characters)

    local compressed = LibDeflate:CompressZlib(data)
    local printable = LibDeflate:EncodeForPrint(compressed)

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Speedy Character Export")
    frame:SetStatusText("Exporting Speedy Character Data")
    frame:SetCallback(
        "OnClose",
        function(widget)
            AceGUI:Release(widget)
        end
    )
    frame:SetLayout("Fill")

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:DisableButton(true)
    editBox:SetLabel(nil)
    editBox:SetText(printable)
    editBox:SetFocus()
    editBox:HighlightText()

    frame:AddChild(editBox)
end

function Speedy:UpgradeDB()
    local dbVersion = self.db.global.DBVersion or 1

    -- nothing to do if already at max db version
    if dbVersion == DB_VERSION then
        return
    end

    while dbVersion < DB_VERSION do
        if dbVersion == 1 then
            -- delete LevelXPMax global table
            if self.db.global.LevelXPMax then
                self.db.global.LevelXPMax = nil
            end

            -- remove XP and XPMax from each LevelTimes
            -- set LevelTimes keys to strings
            for _, char in pairs(self.db.global.Characters) do
                local newLevelTimes = {}
                for levelNum, levelTime in pairs(char.LevelTimes) do
                    newLevelTimes[tostring(levelNum)] = {
                        Played = levelTime.Played,
                        LastUpdated = levelTime.LastUpdated
                    }
                end
                char.LevelTimes = newLevelTimes
            end

            -- completed 1 => 2 upgrade
            dbVersion = 2
            self.db.global.DBVersion = dbVersion
        end
    end
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
    self:UpgradeDB()

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
