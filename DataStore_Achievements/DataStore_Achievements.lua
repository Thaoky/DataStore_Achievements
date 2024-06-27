--[[	*** DataStore_Achievements ***
Written by : Thaoky, EU-Marécages de Zangar
June 21st, 2009
--]]
if not DataStore then return end

local addonName, addon = ...
local thisCharacter

local TableConcat, TableInsert, format, floor, select, time = table.concat, table.insert, format, math.floor, select, time
local GetAchievementCriteriaInfoByID, GetAchievementNumCriteria, GetAchievementCriteriaInfo, GetAchievementInfo = GetAchievementCriteriaInfoByID, GetAchievementNumCriteria, GetAchievementCriteriaInfo, GetAchievementInfo
local GetCategoryList, GetCategoryNumAchievements, GetPreviousAchievement, GetNumCompletedAchievements = GetCategoryList, GetCategoryNumAchievements, GetPreviousAchievement, GetNumCompletedAchievements
local GetTotalAchievementPoints, GetInventorySlotInfo, GetInventoryItemLink, UnitGUID = GetTotalAchievementPoints, GetInventorySlotInfo, GetInventoryItemLink, UnitGUID
local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

-- *** Utility functions ***
local bAnd = bit.band
local bit64 = LibStub("LibBit64")

local function IsAccountBound(flags)
	return bit.band(flags, ACHIEVEMENT_FLAGS_ACCOUNT) == ACHIEVEMENT_FLAGS_ACCOUNT
end

local function DateToInt(month, day, year)
	return year * 10000 + month * 100 + day
end

local function IntDateToStr(intDate)
	local year = floor(intDate / 10000)
	local month = floor((intDate % 10000) / 100)
	local day = intDate % 100
	
	return format("%d:%d:%d", month, day, year)
end

-- *** Scanning functions ***
local CriteriaCache = {}

local function ScanTabards()
	local TABARDS_ACHIEVEMENT_ID = 621

	local tabardCriteriaIDs = {
		2335, 2336, 2337, 2338, 2339, 2340, 2893, 2894, 2895, 2896,
		2897, 2898, 2899, 2900, 2901, 2902, 2903, 2904, 2905, 2906,
		2907, 2908, 2909, 2910, 2911, 2912, 2913, 2914, 2915, 2916,
		2917, 2918, 2919, 2920, 2921, 2922, 2923, 2924, 2925, 2926,
		2927, 2928, 2929, 2930, 2931, 2932, 2933, 6151, 6171, 6172,
		6976, 6977, 6978, 6979, 11298, 11299, 11300, 11301, 11302, 11303,
		11304, 11305, 11306, 11378, 11307, 11308, 11309, 11760, 11761, 12598,
		12599, 12600, 13241, 13242, 16319, 16320, 16321, 16322, 16323, 16324,
		16325, 16326, 16327, 16328, 16329, 16885, 16886, 21692, 21693, 22618,
		22619, 22620, 22621, 22622, 22623, 22624, 22625, 22626
	}

	local criteriaID, icCompleted
	local tabards = thisCharacter.Tabards

	for i = 1, #tabardCriteriaIDs do
		criteriaID = tabardCriteriaIDs[i]
		isCompleted = select(3, GetAchievementCriteriaInfoByID(TABARDS_ACHIEVEMENT_ID, criteriaID))

		tabards[criteriaID] = (isCompleted == true) and true or nil
	end
end

local function ScanSingleAchievement(id, isCompleted, month, day, year, flags, wasEarnedByMe)
--[[
	How achievements are saved :
	- Storage : in the character's table. Account-wide achievements are no longer saved.
	- Structure:
		- If an achievement is fully completed, it is saved in the "Completed" and "CompletionDates" tables.
		- If it is partially complete:
			- There is only 1 criteria, and that criteria is a quantity : saved in "Partial", as a number
			- There is more than 1 criteria:
				- At least one criteria has a progression : saved in "Partial", as a string
				- Every criteria is a simple true/false flag : saved in "PartialBits", into a number (64 bits)
		
		- If an achievement is not completed, not even started, it is not saved at all.
--]]
	if not id or not flags then return end	 -- no id or no flags, exit

	-- Account-wide achievements are no longer saved.
	if IsAccountBound(flags) then return end

	local storage = thisCharacter
	storage.lastUpdate = time()

	--[[ Achievements can have 3 different statuses :

	Completed : the achievement has been completed, so implicitly, all criterias have been completed too, saved in the table "Completed"
	Partially complete : a string of values describes the state of completion, saved in the table "Partial"
	Not started : if an achievement is in neither table, it has not been started, not even a single criteria
	--]]

	-- 1) Fully completed achievements
	local index, bitPos
	
	if isCompleted and wasEarnedByMe then
		local completed = storage.Completed
		bitPos = (id % 64)
		index = ceil(id / 64)

		-- true when completed, all criterias are completed thus
		completed[index] = bit64:SetBit((completed[index] or 0), bitPos)
		storage.CompletionDates[id] = DateToInt(month, day, year)
		
		return
	end

	-- 2) Partially completed achievements (with a single criteria)
	local num = GetAchievementNumCriteria(id)
	
	if num == 1 then
		-- if there's only 1 criteria, we know for sure it hasn't been completed (otherwise the achievement itself would be completed)
		-- so only the quantity matters (and only if it's > 0)
		local _, _, _, quantity = GetAchievementCriteriaInfo(id, 1)
		if quantity and quantity > 0 then
			storage.Partial[id] = quantity
		end
		
		return
	end

	-- 3) Partially completed achievements (with multiple criteria)
	local partialBits = 0
	local hasProgress = false
	wipe(CriteriaCache)

	local critCompleted, quantity, reqQuantity, _
	
	for j = 1, num do
		-- ** calling GetAchievementCriteriaInfo in this loop is what costs the most in terms of cpu time **
		_, _, critCompleted, quantity, reqQuantity = GetAchievementCriteriaInfo(id, j)

		-- MoP fix, some achievements not completed by current alt, but completed by another alt, return that the criteria is completed, even when it's not
		-- This is visible for reputation achievements for example.
		if quantity < reqQuantity then
			critCompleted = false
		end

	   if critCompleted then
	      TableInsert(CriteriaCache, tostring(j))
			
			if num <= 63 then
				partialBits = bit64:SetBit(partialBits, j)
			-- else
				-- we have a problem if more than 64 criteria in an achievement..
			end
	   else
	      if quantity and reqQuantity and quantity > 0 and reqQuantity > 1 then		-- a quantity of 0 = not started, don't save !
	         TableInsert(CriteriaCache, format("%d:%d", j, quantity))
				hasProgress = true
	      end
	   end
	end

	if #CriteriaCache > 0 then		-- if at least one criteria completed, save the entry, do nothing otherwise
		
		if hasProgress then
			storage.Partial[id] = TableConcat(CriteriaCache, ",")
		else
			-- store partial bits as a number (completed criteria 1,4,5 ? set bits 1,4,5
			storage.PartialBits[id] = partialBits
		end
	end
end

local function ScanAllAchievements()
	-- 2021/06/25 : do not wipe information about fully completed achievements, they will not go "uncompleted" any time soon.
	-- The reason is that achievements that are both horde and alliance have different id's, and wiping would cancel the achievement
	-- when logging on with the other faction. (especially for account-wide achievements)

	wipe(thisCharacter.Partial)
	wipe(thisCharacter.PartialBits)

	local cats = GetCategoryList()
	local prevID

	local achievementID, achCompleted, month, day, year, flags, wasEarnedByMe, earnedBy, _

	for k, categoryID in ipairs(cats) do
		for i = 1, GetCategoryNumAchievements(categoryID) do
			achievementID, _, _, achCompleted, month, day, year, _, flags,_, _, _, wasEarnedByMe, earnedBy = GetAchievementInfo(categoryID, i)
			if achievementID then
				ScanSingleAchievement(achievementID, achCompleted, month, day, year, flags, wasEarnedByMe)

				-- track previous steps of a progressive achievements
				prevID = GetPreviousAchievement(achievementID)

				while type(prevID) ~= "nil" do
					achievementID, _, _, achCompleted, month, day, year, _, flags,_, _, _, wasEarnedByMe, earnedBy = GetAchievementInfo(prevID)
					if not achievementID then break end	-- exit the loop if id is invalid
					
					ScanSingleAchievement(achievementID, achCompleted, month, day, year, flags, wasEarnedByMe)
					prevID = GetPreviousAchievement(achievementID)
				end
			end
		end
	end
end

local function ScanProgress()
	local char = thisCharacter
	local total, completed = GetNumCompletedAchievements()

	char.numAchievements = total
	char.numCompletedAchievements = completed
	char.numAchievementPoints = GetTotalAchievementPoints()
end

-- *** Event Handlers ***
local function OnPlayerAlive()
	-- for some reason, since 4.1, the event seems to be triggered repeatedly when a player releases after death, I could not clearly identify the cause
	-- but I could reproduce the issue and work around it by unregistering the event.
	addon:StopListeningTo("PLAYER_ALIVE")

	ScanAllAchievements()
	ScanProgress()
	
	if not isRetail then
		ScanTabards()
	end

	thisCharacter.guid = UnitGUID("player") -- Get the GUID for achievement links
end

-- ** Mixins **
local function GetAccountWideAchievementInfo(achievementID)
	-- 1) Fully completed achievements
	local isCompleted = select(4, GetAchievementInfo(achievementID))
	if isCompleted then
		return true, true			-- The achievement is started and completed
	end
	
	-- 2) Partially completed achievements (with a single criteria)
	local num = GetAchievementNumCriteria(achievementID)
	if num == 1 then
		-- if there's only 1 criteria, we know for sure it hasn't been completed 
		-- (otherwise the achievement itself would be completed)
		return true, nil		-- started, not completed
	end
	
	-- 3) Partially completed achievements (with multiple criteria)
	local critCompleted, quantity, reqQuantity, _

	-- try all criteria, if at least one is completed, then it's a partial completion
	for j = 1, num do
		_, _, critCompleted, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, j)

		-- MoP fix, some achievements not completed by current alt, but completed by another alt, return that the criteria is completed, even when it's not
		-- This is visible for reputation achievements for example.
		if quantity < reqQuantity then
			critCompleted = false
		end

	   if critCompleted then
	      return true, nil		-- started, not completed
	   else
	      if quantity and reqQuantity and quantity > 0 and reqQuantity > 1 then		-- a quantity of 0 = not started, don't save !
	         return true, nil		-- started, not completed
	      end
	   end
	end
	
	-- not started, not completed
	-- implicit return of nil, nil otherwise
end

local function _GetAchievementInfo(character, achievementID, isAccountBound)
	-- account bound are no longer saved, just query the game's API
	if isAccountBound then
		return GetAccountWideAchievementInfo(achievementID)
	end

	local index = ceil(achievementID / 64)

	if character.Completed[index] then				-- if there's a potential index for this id ..
		local bitPos = (achievementID % 64)
		if bit64:TestBit(character.Completed[index], bitPos) then -- .. and if the right bit is set ..
			return true, true			-- .. then achievement is started and completed
		end
	end

	if character.Partial[achievementID] or character.PartialBits[achievementID] then
		return true, nil		-- started, not completed
	end

	-- implicit return of nil, nil otherwise
end

local function GetAccountWideCriteriaInfo(achievementID, criteriaIndex)
	local _, _, critCompleted, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, criteriaIndex)

	-- MoP fix, some achievements not completed by current alt, but completed by another alt, return that the criteria is completed, even when it's not
	-- This is visible for reputation achievements for example.
	if quantity < reqQuantity then
		critCompleted = false
	end
	
	if critCompleted then
		return true, true				-- The criteria is started and completed
	else
		return true, nil, quantity	-- The criteria is started, not completed, + quantity
	end
end

local function _GetCriteriaInfo(character, achievementID, criteriaIndex, isAccountBound)
	-- account bound are no longer saved, just query the game's API
	if isAccountBound then
		return GetAccountWideCriteriaInfo(achievementID, criteriaIndex)
	end

	local achievement = character.PartialBits[achievementID]
	-- if we have partial bits.. check them
	if achievement then
		-- no need for "criteriaIndex - 1" because we do not save partials in bit 0
		local icCompleted = bit64:TestBit(achievement, criteriaIndex)
		
		if icCompleted then
			return true, true			-- .. then criteria is started and completed
		end
		
		return	-- nil, nil : not started, not completed
	end
	
	achievement = character.Partial[achievementID]

	if type(achievement) == "number" then	-- number = only 1 criteria
		return true, nil, achievement			-- started, not complete, quantity
	end

	if type(achievement) == "string" then	-- string = multiple criteria
		
		local index, qty
		for v in achievement:gmatch("([^,]+)") do
			index, qty = strsplit(":", v)

			index = tonumber(index)
			qty = tonumber(qty)

			if criteriaIndex == index then
				local isStarted = true				-- .. the criteria has been worked on
				local isComplete
				if not qty then						-- ..and might even have been completed (no qty means complete)
					isComplete = true
				end

				-- this will return :
					-- true, true, nil		if the criteria is 100% completed
					-- true, nil, value		if the criteria is partially complete
				return isStarted, isComplete, qty
			end
		end
	end
	-- implicit return of nil, nil , nil 	(not started, not complete)
end

local bitset = { 0, 0, 0, 0 }		-- a simple array that will contain the 4 values to store into "criterias"

local function ClearBitSet()
	bitset[1] = 0
	bitset[2] = 0
	bitset[3] = 0
	bitset[4] = 0
end

local function GetCompletionInfo(character, achievementID)
	local completion		-- will contain: finished (0 or 1), month, day, year
	local criterias

	local index = ceil(achievementID / 32)
	if character.Completed[index] then				-- if there's a potential index for this id ..
		local bitPos = (achievementID % 32)
		if bit64:TestBit(character.Completed[index], bitPos) then -- .. and if the right bit is set ..
			-- .. then achievement is started and completed
			local completionDate = character.CompletionDates[achievementID]
			if not completionDate then return end		-- if there's no data yet for this achievement, the link can't be created, return nil

			completion = format("1:%s", IntDateToStr(completionDate))			-- ex: 1:12:19:8		1 = finished, on 12/19/2008
			criterias = "4294967295:4294967295:4294967295:4294967295"		-- 4294967295 = the highest 32-bit value = 32 bits set to 1
		end
	end

	if not completion then	-- if it wasn't a completed achievement, maybe it's a partially completed one
		completion = "0:0:0:-1"

		local num = GetAchievementNumCriteria(achievementID)
		ClearBitSet()

		for criteriaIndex = 1, num do						-- browse all criterias
			local index = ceil(criteriaIndex / 32)		-- store in bitset[1], [2] ..

			local _, isComplete = _GetCriteriaInfo(character, achievementID, criteriaIndex)
			if isComplete then
				local pos = mod(criteriaIndex, 32)		-- pos must be within [1 .. 32]
				pos = (pos == 0) and 32 or pos			-- if the modulo leads to 0, change it to 32
				bitset[index] = bitset[index] + (2^(pos-1))		-- I'll change this to use bit functions later on, for the time being, this works fine.
			end
		end

		criterias = TableConcat(bitset, ":")
	end
	
	return completion, criterias
end

local function GetAccountWideCompletionInfo(achievementID)
	local completion, criterias
	
	local _, isComplete = GetAccountWideAchievementInfo(achievementID)
	if isComplete then
		local _, _, _, _, month, day, year = GetAchievementInfo(achievementID)
		completion = format("1:%d:%d:%d", month, day, year)	-- ex: 1:12:19:8		1 = finished, on 12/19/2008
		criterias = "4294967295:4294967295:4294967295:4294967295"		-- 4294967295 = the highest 32-bit value = 32 bits set to 1
	
	else
		completion = "0:0:0:-1"
		
		local num = GetAchievementNumCriteria(achievementID)
		ClearBitSet()

		for criteriaIndex = 1, num do						-- browse all criterias
			local index = ceil(criteriaIndex / 32)		-- store in bitset[1], [2] ..

			local _, isComplete = GetAccountWideCriteriaInfo(achievementID, criteriaIndex)
			if isComplete then
				local pos = mod(criteriaIndex, 32)		-- pos must be within [1 .. 32]
				pos = (pos == 0) and 32 or pos			-- if the modulo leads to 0, change it to 32
				bitset[index] = bitset[index] + (2^(pos-1))		-- I'll change this to use bit functions later on, for the time being, this works fine.
			end
		end

		criterias = TableConcat(bitset, ":")
	end
	
	return completion, criterias
end

local function _GetAchievementLink(character, achievementID)
	-- information sources :
		-- http://www.wowwiki.com/AchievementLink
		-- http://www.wowwiki.com/AchievementString
	if not character.guid then return end

	local _, name, _, _, _, _, _, _, flags = GetAchievementInfo(achievementID)
	local completion, criterias
	
	if IsAccountBound(flags) then
		completion, criterias = GetAccountWideCompletionInfo(achievementID)
	else
		completion, criterias = GetCompletionInfo(character, achievementID)
	end

	return format("|cffffff00|Hachievement:%s:%s:%s:%s|h\[%s\]|h|r", achievementID, character.guid, completion, criterias, name)
end

local function _IsTabardKnown(character, criteriaID)
	if character.Tabards[criteriaID] then
		return true
	end
end

DataStore:OnAddonLoaded(addonName, function()
	DataStore:RegisterModule({
		addon = addon,
		addonName = addonName,
		characterTables = {
			["DataStore_Achievements_Characters"] = {
				GetNumAchievements = function(character)
					return character.numAchievements
				end,
				GetNumCompletedAchievements = function(character)
					return character.numCompletedAchievements
				end,
				GetNumAchievementPoints = function(character)
					return character.numAchievementPoints
				end,
				GetAchievementInfo = _GetAchievementInfo,
				GetAchievementLink = _GetAchievementLink,
				GetCriteriaInfo = _GetCriteriaInfo,
				IsTabardKnown = _IsTabardKnown,
			},
		}
	})
	
	thisCharacter = DataStore:GetCharacterDB("DataStore_Achievements_Characters", true)
	thisCharacter.Partial = thisCharacter.Partial or {}
	thisCharacter.PartialBits = thisCharacter.PartialBits or {}
	thisCharacter.Completed = thisCharacter.Completed or {}
	thisCharacter.CompletionDates = thisCharacter.CompletionDates or {}
	
	if not isRetail then
		thisCharacter.Tabards = thisCharacter.Tabards or {}
	end
end)

DataStore:OnPlayerLogin(function() 
	addon:ListenTo("PLAYER_ALIVE", function()
		-- for some reason, since 4.1, the event seems to be triggered repeatedly when a player releases after death, I could not clearly identify the cause
		-- but I could reproduce the issue and work around it by unregistering the event.
		addon:StopListeningTo("PLAYER_ALIVE")

		ScanAllAchievements()
		ScanProgress()
		
		if not isRetail then
			ScanTabards()
		end

		thisCharacter.guid = UnitGUID("player") -- Get the GUID for achievement links
	end)
	addon:ListenTo("ACHIEVEMENT_EARNED", function(event, id)
		if id then
			local _, _, _, achCompleted, month, day, year, _, flags, _, _, _, wasEarnedByMe = GetAchievementInfo(id)
			ScanSingleAchievement(id, true, month, day, year, flags, wasEarnedByMe)
			ScanProgress()
		end
	end)
	addon:ListenTo("PLAYER_EQUIPMENT_CHANGED", function(slot)
		-- if it's the tabard slot and we actually equipped one, then scan
		local tabardSlot = GetInventorySlotInfo("TabardSlot")
		
		if slot == tabardSlot and GetInventoryItemLink("player", tabardSlot) then
			ScanTabards()
		end
	end)
end)
