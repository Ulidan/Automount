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
	newCompanionDetected = "COMPANION_LEARNED",
	enteringWorld = "PLAYER_ENTERING_WORLD",
	companionType = "MOUNT",
	gatherSpells = {
		[2366] = true, --Herbalism
		[2368] = true,
		[3570] = true,
		[11993] = true,
		[28695] = true,
		[50300] = true,

		[2575] = true, --Mining
		[2576] = true,
		[3564] = true,
		[10248] = true,
		[29354] = true,
		[50310] = true,

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
	CallCompanion(config.companionType,id)
end

local function mountList()
	sPrint("#: Name")
	local numConpanions = GetNumCompanions(config.companionType)
	for id = 1, numConpanions do
		local _, name, spellId, _, isSummoned, mountType = GetCompanionInfo(config.companionType, id)
		sPrint(format("%d:%s Type:%s",id,name, spellId))
	end
end

local function getMounts()
	local numMounts = GetNumCompanions(config.companionType)
	for id = numMounts, 1, -1 do
		local _, name, spellId, _, isSummoned, mountType = GetCompanionInfo(config.companionType, id)
		internal.mounts[spellId] = {id=id,name=name}
		if isSummoned then
			AutoMountDB.lastMount = id
		end
	end
	dPrint("Automount: Got %d mounts", numMounts)
end

local function remount()
	dPrint("Trying to mount")
	if AutoMountDB.gather and AutoMountDB.lastMount and not IsMounted()
		and not (IsIndoors() or UnitCastingInfo("player")
			or InCombatLockdown() or IsPlayerMoving() or IsSwimming()) then
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
		self:lootClosed()
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
		local mountInfo = internal.mounts[spellId]
		if mountInfo then
			AutoMountDB.lastMount = mountInfo.id
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

function AutoMount:newCompanionDetected()
	print("Debug: New Companion Detected")
	getMounts()
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
	self:RegisterEvent(config.newCompanionDetected, self.newCompanionDetected)
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

local function argList(inString)
	local items={}
	local item
	for item in string.gmatch(inString,"[^,]+") do
		if item then
			table.insert(items,string.trim(item))
		end
	end
	return unpack(items)
end

local function slashHandler(arg)
	if arg then
		if string.lower(arg) == "debug" then
			AutoMountDB.debug = not AutoMountDB.debug
			if AutoMountDB.debug then
				sPrint("Debug on")
			else
				sPrint("Debug off")
			end
			return
		elseif string.lower(arg) == "gather" then
			AutoMountDB.gather = not AutoMountDB.gather
			if AutoMountDB.gather then
				sPrint("Gather mode on")
			else
				sPrint("Gather mode off")
			end
			return
		elseif string.lower(arg) == "list" then
			mountList()
			return
		end
	end
	sPrint"Usage: '/Automount Gather' - Toggle Auto Mounting after gathering"
	sPrint"Usage: '/Automount Debug' - Toggle debug mode"
end

SlashCmdList["AUTOMOUNT"] = slashHandler
SLASH_AUTOMOUNT1 = "/automount"
SLASH_AUTOMOUNT2 = "/am"