require "PregnancyModData";

local PregnancyMoodle = require "PregnancyMoodle";
local SBvars = SandboxVars.Pregnancy;

local function pregnancyProgress(modData)
	return 1 - modData.HoursToLabor / modData.InitialPregnancyDuration;
end

local function consumeExtraCalories(player, calories)
	--print("Pregnancy Logger | PregnancyTraitLogic: consuming extra "..calories.." calories");
	player:getNutrition():setCalories(math.max(-2200, player:getNutrition():getCalories() - calories))
end

local function consumeExtraWater(player, water)
	--print("Pregnancy Logger | PregnancyTraitLogic: consuming extra "..calories.." calories");
	player:getStats():setThirst(math.min(1, player:getStats():getThirst() + water))
end

local function checkForScream(player, modData)
	local modifier = player:getPerkLevel(Perks.Strength) + player:getPerkLevel(Perks.Fitness) + player:getPerkLevel(Perks.Sneak) * 3;
	local stats = player:getStats();
	stats:setPain(math.min(100, stats:getPain() + 5));
	modData.chanceToScream = modData.chanceToScream + math.floor(stats:getPain() / 5);
	local finalChance = math.floor(modData.chanceToScream * (1 - (modifier / 100)));
	print("Pregnancy Logger | checkForScream: Chance to scream: "..finalChance);
	if (ZombRand(101) <= finalChance) then
		modData.chanceToScream = math.max(0, modData.chanceToScream - modifier)
		player:SayShout("*Cri*");
	else
		modData.chanceToScream = modData.chanceToScream + 1;
	end
end

local function oneMinutePregnancyFailUpdate()
	local player = getPlayer();
	local unhappiness = player:getBodyDamage():getUnhappynessLevel(); -- 0-100
	if unhappiness < 25 then
		player:getBodyDamage():setUnhappynessLevel(25);
	end
end

local function oneMinutePregnancySuccessUpdate()
	local player = getPlayer();
	local stats = player:getStats();
	local panic = stats:getPanic(); -- 0-100
	local fear = stats:getFear(); -- 0-1
	if panic > 75 then
		stats:setPanic(75);
	end
	if fear > 0.75 then
		stats:setFear(0.75);
	end
end

local function delayedFitnessGain()
	local player = getPlayer();
	local modData = player:getModData().Pregnancy;
	modData.DelayedFitnessHoursLeft = modData.DelayedFitnessHoursLeft - 1;
	if modData.DelayedFitnessHoursLeft == 0 then
		player:LevelPerk(Perks.Fitness);
		Events.EveryHours.Remove(delayedFitnessGain)
	end
end

local function resolvePregnancyOutcome(player, modData)
	local finalChance = SBvars.BaseChanceToDie;
	print("Pregnancy Logger | resolvePregnancyOutcome: finalChance base: "..finalChance);
	if #modData.MentalStateLast24Hours > 0 then
		local sum = 0
		for _, average in ipairs(modData.MentalStateLast24Hours) do
			sum = sum + average
		end
		local average = sum / #modData.MentalStateLast24Hours
		finalChance = finalChance * (average / 100);
		print("Pregnancy Logger | resolvePregnancyOutcome: finalChance adjusted with mental: "..finalChance);
	end
	finalChance = finalChance - 10 * (player:getPerkLevel(Perks.Doctor) + (player:getPerkLevel(Perks.Strength) + player:getPerkLevel(Perks.Fitness)) / 2);
	print("Pregnancy Logger | resolvePregnancyOutcome: finalChance adjusted with skills: "..finalChance);
	local babyFinalChance = finalChance + 30;
	print("Pregnancy Logger | resolvePregnancyOutcome: babyFinalChance: "..babyFinalChance);
	if modData.ConsumedAlcohol then
		babyFinalChance = finalChance + 15;
		print("Pregnancy Logger | resolvePregnancyOutcome: babyFinalChance adjusted by alcohol drinking: "..babyFinalChance);
	end
	if modData.Smoked then
		babyFinalChance = finalChance + 15;
		print("Pregnancy Logger | resolvePregnancyOutcome: babyFinalChance adjusted by smoking: "..babyFinalChance);
	end
	player:getStats():setFatigue(1);
	local traits = player:getTraits();
	if SBvars.CanDieFromPregnancy and (ZombRand(101) <= finalChance) then
		player:Kill(player);
	elseif (ZombRand(101) <= babyFinalChance) and not player:HasTrait("PregnancyFail") then
		traits:remove("Pregnancy");
		traits:add("PregnancyFail");
		HaloTextHelper.addTextWithArrow(player, getText("UI_trait_PregnancyFail"), true, HaloTextHelper.getColorRed())
		Events.EveryOneMinute.Remove(oneMinutePregnancyFailUpdate);
		Events.EveryOneMinute.Add(oneMinutePregnancyFailUpdate);
	elseif not player:HasTrait("PregnancySuccess") then
		traits:remove("Pregnancy");
		traits:add("PregnancySuccess");
		HaloTextHelper.addTextWithArrow(player, getText("UI_trait_PregnancySuccess"), true, HaloTextHelper.getColorGreen())
		Events.EveryOneMinute.Remove(oneMinutePregnancySuccessUpdate);
		Events.EveryOneMinute.Add(oneMinutePregnancySuccessUpdate);
		Events.EveryHours.Remove(delayedFitnessGain)
		Events.EveryHours.Add(delayedFitnessGain)
	end
	PregnancyMoodle.PregnancyProgressMoodleUpdate(player, 0, true);
	modData.MentalStateLast24Hours = {};
	modData.MentalStateLastHour = {};
end

local function laborOneMinuteUpdate()
	local player = getPlayer();
	local modData = player:getModData().Pregnancy;
	modData.CurrentLaborDuration = modData.CurrentLaborDuration + 1;
	print("Pregnancy Logger | laborOneMinuteUpdate: Labor duration: "..modData.CurrentLaborDuration.."/"..modData.ExpectedLaborDuration.." minutes");
	if modData.CurrentLaborDuration >= modData.SecondStageStart then
		print("Pregnancy Logger | laborOneMinuteUpdate: Second stage");
		checkForScream(player, modData)
	end
	if modData.CurrentLaborDuration == modData.ExpectedLaborDuration then
		-- check if player survives
		SpeedFramework.SetPlayerSpeed(player, 1);
		player:setBlockMovement(false);
		player:setMaxWeightBase(8);
		print("Pregnancy Logger | laborOneMinuteUpdate: removing laborOneMinuteUpdate event")
		Events.EveryOneMinute.Remove(laborOneMinuteUpdate);
		player:getTraits():remove("Pregnancy");
		resolvePregnancyOutcome(player, modData);
		Events.EveryOneMinute.Remove(laborOneMinuteUpdate);
	end
end

local function recordMentalState(player, modData)
	local stress = player:getStats():getStress() * 100; -- 0-1 -> 0-100
	local unhappiness = player:getBodyDamage():getUnhappynessLevel(); -- 0-100
	local panic = player:getStats():getPanic(); -- 0-100
	local fear = player:getStats():getFear() * 100; -- 0-1 -> 0-100
	local mentalHealth = 100 - ((stress + unhappiness + panic + fear) / 4);
	--print("Pregnancy Logger | recordMentalState: mental state this minute: "..mentalHealth)
	table.insert(modData.MentalStateLastHour, mentalHealth)
	if #modData.MentalStateLastHour >= 60 then
		local sum = 0;
		for i = 1, 60 do
			sum = sum + modData.MentalStateLastHour[i];
		end
		local average = sum / 60;
		print("Pregnancy Logger | recordMentalState: mental state last hour: "..average)
		table.insert(modData.MentalStateLast24Hours, average);
		modData.MentalStateLastHour = {};
	end
end

local function startLabor(player)
	print("Pregnancy Logger | startLabor: started/continued labor");
	print("Pregnancy Logger | startLabor: removing oneHourUpdate event")
	Events.EveryHours.Remove(oneHourUpdate);
	player:reportEvent("EventSitOnGround");
	player:setBlockMovement(true);
	print("Pregnancy Logger | startLabor: adding laborOneMinuteUpdate event")
	Events.EveryOneMinute.Add(laborOneMinuteUpdate);
end

local function oneMinuteUpdate()
	local player = getPlayer();
	local modData = player:getModData().Pregnancy;
	local progress = pregnancyProgress(modData);
	recordMentalState(player, modData);
	if progress >= 0.25 then
		consumeExtraCalories(player, (600 * progress) / 1440);
		consumeExtraWater(player, (0.5 * progress) / 1440);
	end
end

local function oneHourUpdate()
	local player = getPlayer();
	local modData = player:getModData().Pregnancy;
	print("Pregnancy Logger | oneHourUpdate: modData.HoursToLabor "..modData.HoursToLabor);
	if modData.HoursToLabor ~= 0 then
		local progress = pregnancyProgress(modData);
		local hide = false;
		PregnancyMoodle.PregnancyProgressMoodleUpdate(player, progress, hide);
		print("Pregnancy Logger | oneHourUpdate: pregnancyProgress "..progress );
		if progress >= 0.25 then
			print("Pregnancy Logger | oneHourUpdate: setting player speed multiplier to ".. 1 - (pregnancyProgress(modData) / 2));
			SpeedFramework.SetPlayerSpeed(player, 1 - (progress / 2));
			local maxWeightBase = 8 * (1 - (progress / 2));
			player:setMaxWeightBase(maxWeightBase);
		end
		modData.HoursToLabor = modData.HoursToLabor - 1;
	elseif modData.InLabor == false then
		modData.InLabor = true;
		startLabor(player);
		Events.EveryOneMinute.Remove(oneMinuteUpdate);
		Events.EveryHours.Remove(oneHourUpdate);
	end
end

local function morningSickness()
	local player = getPlayer();
	local modData = player:getModData().Pregnancy;
	local progress = pregnancyProgress(modData);
	if progress >= 0.05 and progress <= 0.33 then
		player:getBodyDamage():setFoodSicknessLevel(50 + ZombRand(50))
	end
end

local function initializeTraitsLogic(playerIndex, player)
	if player:HasTrait("Pregnancy") and SBvars.RestrictPregnancyToFemales and not player:isFemale() then
		player:Kill(player);
	end
	local modData = player:getModData().Pregnancy;
	if player:HasTrait("Pregnancy") then
		Events.EveryOneMinute.Remove(oneMinuteUpdate);
		Events.EveryOneMinute.Add(oneMinuteUpdate);
		Events.EveryHours.Remove(oneHourUpdate);
		Events.EveryHours.Add(oneHourUpdate);
		Events.OnDawn.Remove(morningSickness);
		Events.OnDawn.Add(morningSickness);
		if modData.InLabor then
			startLabor(player);
		end
	end
	if player:HasTrait("PregnancySuccess") then
		Events.EveryOneMinute.Remove(oneMinutePregnancySuccessUpdate);
		Events.EveryOneMinute.Add(oneMinutePregnancySuccessUpdate);
		if modData.DelayedFitnessHoursLeft ~= 0 then
			Events.EveryHours.Remove(delayedFitnessGain)
			Events.EveryHours.Add(delayedFitnessGain)
		end
	end
	if player:HasTrait("PregnancyFail") then
		Events.EveryOneMinute.Remove(oneMinutePregnancyFailUpdate);
		Events.EveryOneMinute.Add(oneMinutePregnancyFailUpdate);
	end
end

local function clearEvents(character)
	Events.EveryOneMinute.Remove(oneMinuteUpdate);
	Events.EveryHours.Remove(oneHourUpdate);
	print("Pregnancy Logger | System: clearEvents in PregnancyTraitLogic.lua");
end

Events.OnCreatePlayer.Remove(initializeTraitsLogic);
Events.OnCreatePlayer.Add(initializeTraitsLogic);
Events.OnPlayerDeath.Add(clearEvents);
