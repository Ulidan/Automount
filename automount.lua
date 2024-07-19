local addonName, AutoMount = ...
AutoMountDB = AutoMountDB or {}

local config = {
	failed = "UNIT_SPELLCAST_FAILED",
	succeeded = "UNIT_SPELLCAST_SUCCEEDED",
	stopped = "UNIT_SPELLCAST_STOP",
	channelStopped = "UNIT_SPELLCAST_CHANNEL_STOP",
	errEvent = "UI_ERROR_MESSAGE",
	lootClosed = "LOOT_CLOSED",
	bagUpdateDelayed = "BAG_UPDATE_DELAYED",
	newMountAdded = "NEW_MOUNT_ADDED",
	enteringWorld = "PLAYER_ENTERING_WORLD",
	companionType = "MOUNT",
	gatherSpells = {
		[2366] = true, --Herbalism
		[2368] = true,
		[3570] = true,
		[11993] = true,
		[28695] = true,
		[50300] = true,
		[74519] = true,

		[2575] = true, --Mining
		[2576] = true,
		[3564] = true,
		[10248] = true,
		[29354] = true,
		[50310] = true,
		[74517] = true,

		[30427] = true, --Extract Gas
	},
}

local internal = {
	_frame = CreateFrame("frame", nil, UIParent),
	mounts = {},
}

local function sPrint(msg)
	if msg then
		DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00Automount: |cFFFFFFFF"..msg)
	end
end

local function dPrint(...)
	if AutoMountDB.debug then
		sPrint(format(...))
	end
end

local function mount(id)
	if (select(5,C_MountJournal.GetMountInfoByID(id))) then
		C_MountJournal.SummonByID(id)
		return true
	end
	return false
end

local function mountList()
	sPrint("#: Name")
	local Ids = C_MountJournal.GetMountIDs()
	for _,id in pairs(Ids) do
		local name, _, _, _, isUsable = C_MountJournal.GetMountInfoByID(id)
		local mountType = select(5,C_MountJournal.GetMountInfoExtraByID(id))
		if isUsable then
			sPrint(format("%d:%s Type:%d",id,name, mountType))
		end
	end
end

local function addMount(mountId)
	local name, _, _, isActive, _, _, _, _, _, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountId)
	if isCollected and not shouldHideOnChar then
		internal.mounts[name] = mountId
		if isActive then
			AutoMountDB.lastMount = mountId
		end
		return true
	else
		return false
	end
end

local function getMounts()
	local mountIds = C_MountJournal.GetMountIDs()
	local numMounts = 0
	for _,id in pairs(mountIds) do
		numMounts = numMounts + (addMount(id) and 1 or 0)
	end
	dPrint("Automount: Got %d mounts", numMounts)
end

local function remount()
	dPrint("Trying to mount")
	if AutoMountDB.gather and AutoMountDB.lastMount and not IsMounted()
		and not (IsIndoors() or UnitCastingInfo("player")
			or InCombatLockdown() or IsPlayerMoving()) then
		mount(AutoMountDB.lastMount)
	end
end

function AutoMount:lootClosed()
	if internal.gatherTime and internal.gatherTime > GetTime() then
		internal.gatherTime = nil
		remount()
	end
end

function AutoMount:bagUpdateDelayed()
	if internal.isGas then
		C_Timer.After(0.1, function()
			self:lootClosed()
		end)
	end
end

----- event block -------
function AutoMount:unitSpellcast(...)
	local e, unit, _, spellId = ...
	if not unit or unit ~= "player" or not spellId then
		return
	end
	local isGas = spellId == 30427
	if (e == config.succeeded and not isGas) or
		(e == config.channelStopped and isGas) then
		local mountId = C_MountJournal.GetMountFromSpell(spellId)
		if mountId then
			AutoMountDB.lastMount = mountId
		elseif config.gatherSpells[spellId] then
			internal.isGas = isGas
			internal.gatherTime = GetTime() + 1
		else
			return
		end
	elseif e == config.failed and config.gatherSpells[spellId] then
		remount()
	else
		return
	end
	dPrint("Event:%s, Unit:%s, Spell:%d",e, unit, spellId)
end


function AutoMount:newMountAdded(e,mountId)
	print("Debug: New Companion Detected")
	addMount(mountId)
end

function AutoMount:enteringWorld(e, login, reload)
	if login or reload then
		C_Timer.After(1, function()
			getMounts()
		end)
	end
end


local orgErrEvent = UIErrorsFrame:GetScript("OnEvent")
UIErrorsFrame:SetScript("OnEvent", function(...)
	local _, event, p1, p2 = ...
	if event == config.errEvent and internal.checkForFlight and p1 == 50 then
		dPrint("Error handled:\"%s\"",p2)
		return
	end
	return orgErrEvent(...)
end)

function AutoMount:registerEvents()
	self:RegisterEvent(config.failed, self.unitSpellcast)
	self:RegisterEvent(config.succeeded, self.unitSpellcast)
	self:RegisterEvent(config.channelStopped, self.unitSpellcast)
--	self:RegisterEvent(config.stopped, self.unitSpellcast)
	self:RegisterEvent(config.lootClosed, self.lootClosed)
	self:RegisterEvent(config.bagUpdateDelayed, self.bagUpdateDelayed)
	self:RegisterEvent(config.newMountAdded, self.newMountAdded)
	self:RegisterEvent(config.enteringWorld, self.enteringWorld)
end

function AutoMount:RegisterEvent(e, f)
	if f then
		internal._frame[e] = f
	end
	internal._frame:RegisterEvent(e)
end

internal._frame:Hide()
internal._frame:SetScript("OnEvent", function(_, event, ...)
		internal._frame[event](AutoMount, event, ...)
	end)
AutoMount:registerEvents()
----- end of event block ------

local function slashHandler(arg)
	if arg and strtrim(arg) ~= "" then
		if string.lower(arg) == "debug" then
			AutoMountDB.debug = not AutoMountDB.debug
			if AutoMountDB.debug then
				sPrint"Debug on"
			else
				sPrint"Debug off"
			end
		elseif string.lower(arg) == "gather" then
			AutoMountDB.gather = not AutoMountDB.gather
			if AutoMountDB.gather then
				sPrint"Gather mode on"
			else
				sPrint"Gather mode off"
			end
		elseif string.lower(arg) == "list" then
			mountList()
		elseif arg~="" then
			if not IsMounted() then
				for mountName in arg:gmatch("([^;]+)") do
					local mount1Id = internal.mounts[mountName:trim()]
					if mount1Id and mount(mount1Id) then
						return
					end
				end
				sPrint"Couldn't find mountable mount in list"
			end
			return
		end
	else
		sPrint"Usage: '/Automount' or '/am'"
		sPrint"Usage: '/Automount mount1;mount2;...' - mounts the first mountable mount from a list of mounts."
		sPrint"Usage:     Example: '/am Sea Turtle;Swift Red Gryphon;Charger'"
		sPrint"Usage: '/Automount Gather' - Toggle Auto Mounting after gathering."
		sPrint"Usage: '/Automount Debug' - Toggle debug mode."
	end
end

SlashCmdList["AUTOMOUNT"] = slashHandler
SLASH_AUTOMOUNT1 = "/automount"
SLASH_AUTOMOUNT2 = "/am"