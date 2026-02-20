import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, CAPTION, DIV, METER, SPAN, TABLE, TD, TH, TR} = lindt; //autoimport

let gamestate = { };
//Traits can be positive or negative. For the display (both status and control),
//it's easier to treat them as alternatives. This is kinda like an L10n table
//and could be expanded into one.
const trait_labels = {
	aggressiveP: "Aggressive",
	aggressiveN: "Passive",
	headstrongP: "Headstrong",
	headstrongN: "Prudent",
	braveP: "Brave",
	braveN: "Cowardly",
};
const trait_display_order = "aggressive headstrong brave".split(" ");
const stat_display_order = ["STR", "DEX", "CON", "INT", "WIS", "CHA"];
const BASE_MONSTER_XP = 100, BASE_BOSS_XP = 150; //Monster XP increases if it's above your level. Boss XP increases by its level regardless.
const BASELEVEL_ADVANCEMENT_RATE = 30; //The base level will increase every this-many rooms.
const TICK_LENGTH = 1000; //Normal combat tick. It may be worth reducing this to 100ms and having intermediate ticks.
const MAX_PATHWAY_LENGTH = 20; //Ideally this should be more than can be seen on any reasonable screen

function unlock_trait(t) {if (!gamestate.traits[t]) gamestate.traits[t] = Math.random() / 2 - 0.25;}

//Bosses are defined in sequence. You will never encounter a later boss before an earlier one.
//If you have somehow already defeated a boss, but a new one is created earlier, you'll likely
//meet the new boss fairly soon.
//TODO: Have a "boss rush" special action that respawns every boss from the beginning, in order,
//and lets you kill them. This will ensure that their death triggers all fire.
//TODO: Allow bosses to have special abilities like parrying attacks. They'll need to hook into
//the combat system.
//TODO: Have some boss that unlocks the bow, giving you a grade 1 bow (or maybe his level) to start with.
const bosses = [{
	minlevel: 5, //Boss will not spawn until the baselevel is at least this
	level: 10, //The boss's actual level as will be used for damage calculations
	hpmul: 1.1, //Calculate normal hitpoints for a monster of the boss's level, then multiply by this.
	name: "Snowman", //Short name, used in damage messages
	longname: "Evil Snowman of Doom", //Name shown once upon encounter, and again on death
	ondeath() {unlock_trait("headstrong");},
}];

//Weighted selection from a collection of options. Uses the absolute value of the weight, so -3.14 is equivalent to 3.14.
function weighted_random(weights) {
	let totweight = 0;
	for (let w of Object.values(weights)) totweight += w < 0 ? -w : w;
	let selection = Math.random() * totweight; //Yes, this isn't 100% perfect, but it's close enough
	for (let [t, w] of Object.entries(weights)) if ((selection -= (w < 0 ? -w : w)) < 0) return t;
}

//Flat random. Equivalent to weighted_random({choice1: 1, choice2: 1, choice3: 1, ...})
function random_choice(options) {
	return options[Math.floor(Math.random() * options.length)];
}

const messages = ["Starting on an adventure!"];
function msg(txt) {
	messages.push(txt);
	if (messages.length > 6) messages.shift();
}

//A (de)buff is an object identifying a series of stats to be affected, and has
//a _duration that counts the number of encounters that it will last for.
let stat_buff = { }, incoming_damage_multiplier = 1.0;
function decay_buffs(amt) {
	//Decay all buffs by the given amount and recalculate what's been affected
	if (amt) for (let i = 0; i < gamestate.buffs.length; ++i)
		if ((gamestate.buffs[i]._duration -= amt) <= 0) {
			const buff = gamestate.buffs.splice(i--, 1)[0];
			for (let attr in buff) if (attr !== "_duration")
				gamestate.stats[attr] -= buff[attr];
		}
	//Check all stats that have been affected by buffs so they can be coloured.
	stat_buff = { };
	for (let buff of gamestate.buffs)
		for (let attr in buff)
			if (attr !== "_duration")
				if (stat_buff[attr]) stat_buff[attr] += buff[attr];
				else stat_buff[attr] = buff[attr];
	//Damage reduction is defined as the amount of additional damage required to inflict a
	//certain amount of resultant damage. Thus 10% DR does not reduce your incoming damage
	//by 10%, but it means that it takes 10% more to hurt you as much - that is, it takes
	//11 of a monster's hit to inflict 10 points of damage. This stacks linearly; if you
	//have two sources of 10% DR, this makes 20% DR, requiring 12 of hit to achieve 10 dmg.
	//The number stored in gamestate.stats.dr is a percentage eg 20 for 20%, and should
	//usually be an integer; for efficiency, we precompute 100/(100+gamestate.stats.dr)
	//which is stored as incoming_damage_multiplier.
	incoming_damage_multiplier = 100 / (100 + gamestate.stats.dr);
	//Minor hack: If you have damage reduction, show this as a constitution modifier.
	if (gamestate.stats.dr) stat_buff.CON = gamestate.stats.dr;
	console.log("Buffs decayed, now", stat_buff);
}
function apply_buff(buff) {
	for (let attr in buff) if (attr !== "_duration")
		gamestate.stats[attr] += buff[attr];
	gamestate.buffs.push(buff);
	decay_buffs(0);
}
function buff_color(modifier) {
	if (!modifier) return "";
	if (modifier > 0) return "boosted";
	if (modifier < 0) return "reduced";
	return "altered"; //If for some reason we have a non-comparable change, make it yellow
}

function recalc_next_boss() {
	//Scan the bosses, find which is next, and record that. If all bosses have been defeated,
	//gamestate.bosses._next >= bosses.length; gamestate.bosses._next_level is the level at
	//which that boss can first spawn.
	gamestate.bosses._next_level = Infinity;
	for (var boss = 0; boss < bosses.length; ++boss)
		if (!gamestate.bosses[bosses[boss].name]) {gamestate.bosses._next_level = bosses[boss].minlevel; break;}
	gamestate.bosses._next = boss;
}

function recalc_max_hp() {
	const maxhp = Math.ceil(10 * (1.04 ** gamestate.stats.level) * (1.15 ** gamestate.stats.CON));
	//Whenever your max HP changes, which will usually be a level-up, restore full health.
	if (maxhp !== gamestate.stats.maxhp) gamestate.stats.maxhp = gamestate.stats.curhp = maxhp;
}
function hero_melee_damage() {
	return Math.ceil(
		(1.05 ** gamestate.stats.level)
		* (1.1 ** gamestate.stats.STR)
		* (gamestate.equipment.sword / gamestate.world.baselevel)
		* (Math.random() * 0.4 + 0.8)
	);
}
function hero_ranged_damage() {
	return Math.ceil(
		(1.025 ** gamestate.stats.level)
		* (1.1 ** gamestate.stats.DEX)
		* (gamestate.equipment.BOW / gamestate.world.baselevel)
		* (Math.random() * 0.4 + 0.8)
	);
}
function enemy_max_hp(level) {
	return Math.ceil(3 * (1.17 ** level) * (Math.random() * 0.5 + 0.75)); //Enemy hitpoints will be +/-25% of the basic calculation
}
function enemy_melee_damage(level) {
	return Math.ceil(
		(1.15 ** level)
		* (gamestate.world.baselevel / gamestate.equipment.armor) //Note that armor is functionally a damage reduction effect
		* (Math.random() * 0.6 + 0.70)
	);
}

function take_damage(dmg) {
	dmg *= incoming_damage_multiplier; //Note that damage MAY be fractional.
	if (dmg >= gamestate.stats.curhp) {
		//You died, Mr Reynolds.
		//TODO: Reduce XP or add an XP gain penalty for a while
		msg("THE HERO DIED");
		//But hey, death isn't the end!
		gamestate.world.delay = [0, 10, "::respawn", "DEAD"];
		gamestate.stats.curhp = 0;
		return;
	}
	gamestate.stats.curhp -= dmg;
}

const callbacks = {
	respawn() {
		let newloc = -1;
		for (let l = 0; l < gamestate.world.pathway.length; ++l) {
			const loc = gamestate.world.pathway[l];
			if (loc.type === "respawn" && loc.state === "current") newloc = l; //TODO: There should only be one of these.
		}
		if (newloc === -1) {msg("NO RESPAWN CHAMBER!"); newloc = 0;} //Shouldn't happen.
		for (let l = newloc; l <= gamestate.world.location; ++l)
			gamestate.world.pathway[l].progress = 0;
		gamestate.world.location = newloc;
		gamestate.world.direction = "advancing";
		gamestate.world.delay = [0, 5, "emerge", "Respawning..."];
		gamestate.stats.curhp = gamestate.stats.maxhp;
		//Okay. Now the big one: Update traits.
		//First, look at the requested traits. Note that there could be junk in the requests[] mapping, so
		//we whitelist to valid traits. A trait is valid if and only if it is in the trait_display_order
		//AND you already have some of that trait. (New traits get unlocked by defeating bosses, and you
		//will always get a little of it when that happens.)
		//NOTE: Currently using winner-takes-all voting; if Aggressive has 8 votes and Passive has 7, you
		//will without a doubt become more aggressive. It may be better instead to randomly sample.
		let top_trait = "", top_dir = "", top_count = 0;
		for (let t of trait_display_order) {
			if (!gamestate.traits[t]) continue;
			if (gamestate.requests[t + "N"] > top_count) top_count = gamestate.requests[(top_trait = t) + (top_dir = "N")];
			if (gamestate.requests[t + "P"] > top_count) top_count = gamestate.requests[(top_trait = t) + (top_dir = "P")];
		}
		gamestate.requests = { }; ws_sync.send({cmd: "cleartraitreqs"}); //After each respawn, all requests are consumed.
		if (top_count) {
			const cur_dir = gamestate.traits[top_trait] > 0 ? "P" : "N";
			if (cur_dir === top_dir) {
				//Strengthen the current trait. For example, you're already Aggressive and the request was for more aggressiveness.
				gamestate.traits[top_trait] += Math.random() / 2 + 0.25; //Empower it by 0.25-0.75
			} else {
				//Weaken the current trait, which might flip it.
				const effect = Math.random() + 0.5;
				if (effect > Math.abs(gamestate.traits[top_trait])) {
					//Flip the trait - reset it to a starting trait value in the opposite direction.
					gamestate.traits[top_trait] = Math.random() / 4 + 0.25; //Starting strength of 0.25-0.5
					if (top_dir === "N") gamestate.traits[top_trait] *= -1;
				}
				else gamestate.traits[top_trait] -= effect; //Weaken the trait but keep it as is.
			}
		}
		//Else there were no requests - Hero retains his current traits.
		save_game();
	},
};

//Calculate the level at which something should spawn
//Whenever an enemy/item/equipment is spawned, it is given a level. This comes from a base level, a random component, and possibly a softcap.
//The base level starts at 1, and increases by 1 every time the hero "ought to" level up (probably some number of squares traversed). Ideally,
//the hero should remain approximately at the base level. If he's underlevelled, enemies will be worth more XP and items will be better; if he's
//overlevelled, enemies will be worth reduced XP, possibly a pittance, and items will be the same or worse than current. So it should balance.
//The random component is Math.trunc(random(20)-10), capped at +/- half of the base level.
//For every undefeated boss whose level is less than the base level, halve the excess levels.
/*
  - Example: Base level is 11, random +4, but you have yet to defeat the level 10 boss. The softcap applies to the 5 levels beyond 10, halving
    them, so the actual spawned level will be Math.trunc(boss+(level-boss)/2) which works out to 12.
  - Example: Base level is 57, random -3, but you have not defeated the level 50 boss or the level 40 boss. Start with the earliest undefeated:
    - L40: boss+(level-boss)/2 = 40+(54-40)/2 = 47
    - L50: Using the result of the previous calculation, 47, we're already below the level 50 cutoff, so no further softcapping.
  - Example: Base level is 63, random +1, still haven't defeated either level 50 or level 40.
    - L40: 40+(64-40)/2 = 52
    - L50: 50+(52-50)/2 = 51
    - The effective spawn level will be 51.
*/
function spawnlevel() {
	let level = gamestate.world.baselevel;
	let rand = Math.min(level/2, 10); //Spread by +/- 10 levels each way, but not more than half the base level
	level += Math.trunc(Math.random() * rand*2 - rand);
	//Softcap based on undefeated bosses
	for (let boss of bosses) if (!gamestate.bosses[boss.name]) {
		//Excess levels above the boss's minlevel get halved.
		level -= Math.max(0, Math.floor((level - boss.minlevel) / 2));
	}
	return level;
}

//ENCOUNTER OPTIONS
const encounter = {
	respawn: {
		create() {
			//Respawner states:
			//unreached - new, hasn't yet been tagged
			//reached - has been activated, but isn't current
			//current - where the Hero will respawn
			//When a respawner becomes current, any existing current respawner becomes Reached.
			return {type: "respawn", state: "unreached"};
		},
		action(loc) {
			if (loc.state !== "current") {
				//Set all current respawners to "reached". Note that there should only be one,
				//and it should be on the current path (not a branch). You should never go
				//backwards past a respawner, so you should never switch paths.
				for (let loc of gamestate.world.pathway)
					if (loc.type === "respawn" && loc.state === "current") loc.state = "reached";
				loc.state = "current";
			}
			gamestate.world.direction = "advancing"; //Once you run back as far as a respawner, there's no reason to keep retreating.
		},
		emerge(loc) {
			msg("Your hero emerges from respawn.");
		},
		desire: {braveN: 3, headstrongN: 3},
		render(loc) {return "Respawn";},
	},
	clear: {
		create() {return {type: "clear"};},
		desire: {braveN: 5},
		render(loc) {return "";},
	},
	enemy: {
		create() {return {type: "enemy", level: spawnlevel()};},
		enter(loc) {
			if (!loc.maxhp) {
				//Make a decision. Fight, flee, or move past? Moving past is
				//only an option if we massively outlevel. Attempting to flee
				//may result in the monster getting a free hit first.
				const t = weighted_random(gamestate.traits);
				const trait = t + (gamestate.traits[t] < 0 ? "N" : "P");
				let choice = "attack"; //By default, we fight.
				switch (trait) {
					case "aggressiveP": break; //Aggressive heroes will fight every time.
					case "aggressiveN": break; //Passive heroes don't really care so they'll fight, it's the straight-forward option. TODO: Prefer to move past if that's an option.
					case "headstrongP": break; //Headstrong heroes will take any fight, no matter how scary.
					case "headstrongN": if (loc.level >= gamestate.stats.level) choice = "flee"; break; //Prudent heroes will avoid dangerous fights.
					case "braveP": break; //TODO: Bypass any enemy that would be dishonourable to fight
					case "braveN": choice = "flee"; break; //Cowards can't block warriors.
				}
				if (choice === "flee") {
					//The enemy gets a free hit. TODO: Make this probablistic based on levels and stats?
					take_damage(enemy_melee_damage(loc.level));
					gamestate.world.direction = "retreating";
					return;
				}
				//Alright, let's fight.
				loc.maxhp = loc.curhp = enemy_max_hp(loc.level);
				loc.state = Math.random() < 0.5 ? "herohit" : "enemyhit"; //TODO: Randomize this based on stats
			}
		},
		action(loc) {
			//If we're fighting, have a round of combat.
			if (!loc.curhp) return;
			if (loc.state === "herohit") {
				//Hero gets a melee attack on the enemy!
				const dmg = hero_melee_damage();
				if (dmg >= loc.curhp) {
					loc.curhp = 0;
					msg("Enemy defeated!"); //TODO: Get some nicer messages, possibly using level range to determine an enemy name
					loc.state = "dead";
					if (loc.level < gamestate.stats.level - 10) gamestate.stats.xp += 1; //Minimal XP for super-low-level enemies
					else {
						const diff = loc.level - gamestate.stats.level;
						gamestate.stats.xp += Math.ceil(BASE_MONSTER_XP * (1.17 ** diff));
					}
					return "hold";
				}
				loc.curhp -= dmg;
				loc.state = "enemyhit";
			} else {
				//Uh oh, here comes a blow in response!
				take_damage(enemy_melee_damage(loc.level)); //Might result in death.
				loc.state = "herohit";
			}
			return "hold";
		},
		desire: {aggressiveP: 10, headstrongP: 5, braveP: 5, braveN: -5},
		render(loc) {
			if (loc.maxhp && !loc.curhp) return "Corpse";
			return "Enemy";
		},
	},
	boss: {
		create() {
			//When spawning a boss, check to see if other bosses exist; if so,
			//spawn sequential bosses (for a boss rush). If we're out of bosses
			//for the current level, instead spawn a regular enemy.
			//TODO: What about branches?
			let boss = gamestate.bosses._next;
			for (let enc of gamestate.world.pathway) {
				if (enc.type === "boss" && enc.boss <= boss) {
					++boss;
					if (boss >= bosses.length || bosses[boss].minlevel > gamestate.world.baselevel)
						return encounter.enemy.create();
				}
			}
			return {type: "boss", boss};
		},
		enter(loc) {
			const boss = bosses[loc.boss];
			if (!loc.maxhp) {
				//Make a decision. Fight or flee? This is a big and nasty boss.
				const t = weighted_random(gamestate.traits);
				const trait = t + (gamestate.traits[t] < 0 ? "N" : "P");
				let choice = "attack"; //By default, we fight.
				switch (trait) {
					case "aggressiveP": break; //Aggressive heroes will fight every time.
					case "aggressiveN": choice = "flee"; break; //Passive heroes would prefer simpler enemies and will not take on a boss.
					case "headstrongP": break; //Headstrong heroes will take any fight, no matter how scary.
					case "headstrongN": if (boss.level >= gamestate.stats.level) choice = "flee"; break; //Prudent heroes will avoid dangerous fights.
					case "braveP": break; //Brave heroes ALWAYS fight bosses
					case "braveN": choice = "flee"; break; //Cowards can't block warriors.
				}
				if (choice === "flee") {
					//Bosses always get the free hit. (Regular enemies might not.)
					take_damage(enemy_melee_damage(boss.level));
					gamestate.world.direction = "retreating";
					return;
				}
				//Alright, let's fight.
				loc.maxhp = loc.curhp = enemy_max_hp(boss.level) * boss.hpmul;
				loc.state = "enemyhit"; //Bosses always get first strike.
				msg("FIGHT: " + boss.longname);
			}
		},
		action(loc) {
			//If we're fighting, have a round of combat.
			if (!loc.curhp) return;
			const boss = bosses[loc.boss];
			if (loc.state === "herohit") {
				//Hero gets a melee attack on the enemy!
				const dmg = hero_melee_damage();
				if (dmg >= loc.curhp) {
					loc.curhp = 0;
					msg("The " + boss.longname + " is defeated!");
					gamestate.bosses[boss.name] = +new Date;
					if (boss.ondeath) boss.ondeath();
					recalc_next_boss();
					loc.state = "dead";
					//Boss XP is functionally fixed, regardless of the hero's level.
					//Note that this number goes up fairly fast, but will take a long
					//time to exceed the cost of gaining a level (which approximates to
					//phi ** level).
					gamestate.stats.xp += Math.ceil(BASE_BOSS_XP * (1.25 ** boss.level));
					return "hold";
				}
				loc.curhp -= dmg;
				loc.state = "enemyhit";
			} else {
				//Uh oh, here comes a blow in response!
				take_damage(enemy_melee_damage(boss.level)); //Might result in death.
				loc.state = "herohit";
			}
			return "hold";
		},
		//TODO: Prudent should want this if the level is reasonable.
		desire: {aggressiveP: 20, headstrongP: 10, braveP: 20},
		render(loc) {return bosses[loc.boss].name;},
	},
	equipment: {
		create() {return {type: "equipment", slot: "unknown", level: spawnlevel() + 1};}, //Slot becomes known when the item is collected
		enter(loc) {
			if (loc.slot === "unknown") {
				//Not yet collected!
				loc.slot = random_choice(Object.keys(gamestate.equipment));
				if (gamestate.equipment[loc.slot] < loc.level) {
					//It's an upgrade! Take some time to pick it up.
					gamestate.world.delay = [0, loc.slot === "armor" ? 10 : 5, "equip", "Equipping..."];
					msg("Equipping a grade " + loc.level + " " + loc.slot); //TODO: Word them differently
				}
			}
		},
		equip(loc) {
			gamestate.equipment[loc.slot] = loc.level; //Done equipping it, let's go!
		},
		desire: {headstrongN: 10},
		render(loc) {
			if (loc.slot === "unknown") return "Equipment";
			return "G" + loc.level + " " + loc.slot;
		},
	},
	item: {
		create() {return {type: "item", item: "unknown", level: spawnlevel()};},
		enter(loc) {
			if (loc.item === "unknown") {
				loc.item = random_choice(["flash", "STR", "DEX", "INT", "WIS", "CON"]);
				switch (loc.item) {
					case "flash":
						gamestate.world.delay = [0, 3, "flashed", "Oops..."];
						break;
					case "STR": case "DEX": case "INT": case "WIS": case "CON":
						gamestate.world.delay = [0, 3, "statboost", "Drinking..."];
						break;
					default: msg("BUGGED ITEM " + loc.item);
				}
			}
		},
		flashed(loc) {
			gamestate.stats.xp += Math.ceil(BASE_MONSTER_XP * 4 * (1.4 ** loc.level));
			DOM("#pathway").classList.add("flashed");
			setTimeout(() => DOM("#pathway").classList.remove("flashed"), 4000);
		},
		statboost(loc) {
			//Higher level potions have the same effect but last longer.
			//Note that, currently, you can drink two STR potions and be
			//even stronger, rather than stacking the durations.
			const _duration = 15 + (loc.level - gamestate.world.baselevel);
			//Constitution is a special case because buffing CON is messy.
			//So instead of giving you +5 CON, which would give you roughly
			//double the horsepower, we give a 33% damage modifier, meaning
			//that it takes 40 damage to deal 30 to you - more in line with
			//the effect that +5 STR gives in the other direction.
			if (loc.item === "CON") apply_buff({_duration, dr: 33});
			else apply_buff({_duration, [loc.item]: 5});
		},
		desire: {headstrongN: 10, aggressiveN: 3},
		render(loc) {
			if (loc.item === "unknown") return "Item";
			return loc.item; //TODO: Localize these
		},
	},
	branch: {
		create() {
			//A branch needs to have its own pathway in it. Note that its location gets a fixed value; this
			//makes the populate() function simpler, and has no other effect.
			const ret = {type: "branch", pathway: [], location: -1};
			gamestate.world.blfrac -= 3; //The three preview cells don't count to base level advancement.
			populate(ret);
			return ret;
		},
		enter(loc) {
			if (gamestate.world.direction === "retreating") {
				//He's running away and will definitely switch paths.
				gamestate.world.direction = "advancing";
				gamestate.world.delay = [0, 10, "switchpath", "Going the other way..."];
			}
			else gamestate.world.delay = [0, 10, "pickpath", "Contemplating..."];
		},
		pickpath(loc) {
			//Okay. So. Got a few options here.
			//1) For every encounter, multiply each trait's desire for it by the trait's strength.
			//2) Pick one trait at random (based on trait weights) and use that trait's desire.
			//3) Pick one trait and use both its positive and negative effects?
			//Also once the scores are calculated, we can either:
			//1) Pick whichever branch has the higher score, even if it's a marginal difference
			//2) Take a weighted random selection between them - which can be simplified since there's just two options
			//For now, picking one trait and the max score path.
			const t = weighted_random(gamestate.traits);
			const trait = t + (gamestate.traits[t] < 0 ? "N" : "P");
			let score1 = 0, score2 = 0;
			for (let i = 0; i < 3; ++i) { //There should always be at least 3 cells ahead of us. If there are more, we can't see beyond three anyway.
				const enc1 = loc.pathway[i], enc2 = gamestate.world.pathway[gamestate.world.location + 1 + i];
				score1 += encounter[enc1.type].desire[trait] || 0;
				score2 += encounter[enc2.type].desire[trait] || 0;
			}
			if (score1 > score2) this.switchpath(loc);
		},
		switchpath(loc) {
			//To switch, we actually mutate both paths. However, we also flag the
			//branch so that we invert the display; the 2D view, when implemented,
			//will use this to know that the display should be flipped back to
			//compensate.
			loc.flipped = !loc.flipped;
			loc.pathway = gamestate.world.pathway.splice(gamestate.world.location+1, Infinity, ...loc.pathway);
		},
		desire: {headstrongN: 3},
		render(loc) {return "Branch";},
	},
};

//The cost to advance past the Nth level is given by the Nth Fibonacci number. This gives
//several cheap levels to start, but then requires more and more to advance.
function tnl(level) {
	let a = 1, b = 1;
	for (let i = 1; i < level; ++i) [a, b] = [b, b + a];
	return b * 1000;
}

function TWO_COL(elements) {
	let rows = [];
	for (let i = 0; i < elements.length; i += 2) {
		if (!elements[i]) rows.push(TR(TD({colSpan: 2}, elements[i+1]))); //No heading, span the cell across both
		else rows.push(TR([TH(elements[i]), TD(elements[i+1])]));
	}
	return TABLE({class: "twocol"}, rows);
}

function populate(world) {
	//First, populate the world. We need to have enough behind us to draw, our current
	//location, and three cells ahead of us.
	while (world.location >= world.pathway.length - 3) {
		//Choose an encounter type.
		//TODO: Dynamically adjust these weights according to circumstances;
		//for example, be generous with equipment if all items are subpar, or
		//offer more enemies if you have good gear.
		//Measure off the distance from certain things. Note that a branch is itself a world,
		//but since it's a branch, it implicitly starts with a branch.
		//TODO: After a branch, track the true distance to respawners (and potentially branches,
		//if it's convenient to do so). Might require a back-reference of some sort - a branch
		//could need a parent node.
		let distance = {respawn: world.type === "branch" ? 0 : 1000, branch: world.type === "branch" ? 0 : 20};
		for (let enc of world.pathway) {
			++distance.respawn; ++distance.branch;
			distance[enc.type] = 0;
		}
		const weights = {
			//Respawners become more likely as you get further from one,
			//and (not shown here) guaranteed to spawn once you're too far.
			respawn: distance.respawn < 8 ? 0 : distance.respawn,
			clear: 5,
			enemy: 15,
			equipment: 2,
			item: 4,
			boss: gamestate.world.baselevel >= gamestate.bosses._next_level ? 3 : 0, //If there are no suitable bosses, it will spawn a regular enemy instead.
			branch: distance.branch < 3 ? 0 : distance.branch,
		};
		let enctype;
		//First, are there any guaranteed spawn demands?
		//if (boss rush mode) {if (weights.boss) enctype = "boss"; else boss rush mode ends}
		if (distance.respawn >= 15) enctype = "respawn"; //NOTE: This figure includes the 3-square advancement
		//else if (there's a user-provided item spawn requested) enctype = "item";
		//Otherwise, weighted random
		else enctype = weighted_random(weights);
		if (!enctype || !encounter[enctype]) break; //Shouldn't happen - for some reason nothing can spawn.
		const enc = encounter[enctype].create();
		if (!enc.distance) enc.distance = Math.max(Math.floor(Math.random() * spawnlevel()), 10); //Distances tend to increase as the game progresses
		enc.progress = 0;
		if (world.pathway.push(enc) > MAX_PATHWAY_LENGTH) {
			world.pathway.shift(); //Discard the oldest
			--world.location;
		}
		//Every time we spawn a new location, advance the base level by a fraction.
		//Special case: Reduce this when we create a branch, to compensate for the three-room preview.
		//The base level may not exceed the hero's level by more than 10.
		if (++gamestate.world.blfrac > BASELEVEL_ADVANCEMENT_RATE && gamestate.world.baselevel < gamestate.stats.level + 10) {
			++gamestate.world.baselevel;
			gamestate.world.blfrac = 0;
		}
	}
}

function change_encounter(dir) {
	gamestate.world.location += dir;
	populate(gamestate.world); //Check if we need to generate some more pathway. Won't be needed if dir is -1 but it doesn't hurt.
	decay_buffs(1);
	//Does this need to become its own function, eg location_trigger("enter") ?
	const location = gamestate.world.pathway[gamestate.world.location];
	const handler = encounter[location.type].enter; if (handler) handler(location);
}
	
function pathway_background(pos, enc) {
	//Transition from future colour to past colour with a progress bar in the current encounter
	if (pos === 0 && enc.progress) {
		const progress = enc.progress * 100 / enc.distance;
		return "linear-gradient(to right, #88f, #88f " + progress + "%, aliceblue " + progress + "%, aliceblue)";
	}
	//For fully-past and fully-future cells, show a solid cell of that colour, possibly adorned with a health bar.
	const col = pos < 0 ? "#88f" : "aliceblue";
	//For the current cell, if it is an enemy (with max hitpoints), show the health bar.
	if (enc.curhp && enc.maxhp) {
		const health = enc.curhp / enc.maxhp * 100;
		return "linear-gradient(to bottom, " + col + " 10%, transparent 10% 20%, " + col + " 20%), linear-gradient(to right, red " + health + "%, blue " + health + "%)";
	}
	return col;
}

//NOTE: The game tick is not started until we first receive status from the server, but
//after that, it will continue to run even if we get disconnected.
let ticking = null, basetime, curtick = 0;
function gametick() {
	const nowtick = (performance.now() - basetime) / TICK_LENGTH; //Note that this may be fractional
	//Whenever this function is called, update game state for all ticks that have happened
	//between lastticktime and now. If the page lags out, we should still be able to do all
	//game ticks (albeit delayed), so we'll catch up before trying to render.
	while (curtick < nowtick) {
		++curtick;
		populate(gamestate.world);

		//Take a step!
		//Does the current location demand more action? Time delays are counted in ticks.
		if (gamestate.world.delay) {
			if (++gamestate.world.delay[0] >= gamestate.world.delay[1]) {
				//Delay is over. Call the callback.
				const cb = gamestate.world.delay[2];
				delete gamestate.world.delay;
				//Global callbacks may require additional args, so hand them the delay array
				if (cb.startsWith("::")) callbacks[cb.slice(2)](gamestate.world.delay);
				else {
					//Location callbacks should have all their parameterization done by
					//the location object itself, so pass them that instead.
					const location = gamestate.world.pathway[gamestate.world.location];
					encounter[location.type][cb](location);
				}
			}
			continue; //Note that this is skipping state-based updates currently, maybe this isn't good
		}
		const location = gamestate.world.pathway[gamestate.world.location];
		const handler = encounter[location.type].action;
		const result = handler && handler(location);
		//The handler may have changed state. The last step is always to move, either advance or retreat.
		if (result === "hold") ; //Stay here this turn. Doesn't overwrite the direction but does override it.
		else if (gamestate.world.direction === "advancing") {
			if (++location.progress >= location.distance) change_encounter(1);
		} else if (gamestate.world.direction === "retreating") {
			if (--location.progress <= 0) change_encounter(-1);
		} //Otherwise something's holding us here.
		//TODO: If advancing and the next location has an enemy, and you have a bow, chance to take a bow shot

		//Finally, check state-based updates.
		if (!gamestate.stats.prevlevel) gamestate.stats.prevlevel = tnl(gamestate.stats.level - 1);
		if (!gamestate.stats.nextlevel) gamestate.stats.nextlevel = tnl(gamestate.stats.level);
		//In the unlikely event that you one-shot more than one level's worth of XP, level up once
		//per tick at most. In fact, if there's any sort of animation for the level up effect, we
		//need to block further advancement until that animation is complete.
		if (gamestate.stats.xp >= gamestate.stats.nextlevel) {
			gamestate.stats.prevlevel = gamestate.stats.nextlevel;
			gamestate.stats.nextlevel = tnl(++gamestate.stats.level);
			for (let i = 0; i < 3; ++i) {
				//Boost some stat. Let the traits decide.
				//There is a baseline chance of catching any stat.
				const weights = {STR: 0.1, DEX: 0.1, CON: 0.1, INT: 0.1, WIS: 0.1, CHA: 0.1};
				for (let [t, w] of Object.entries(gamestate.traits)) {
					if (!w) continue;
					if (w < 0) {t += "N"; w = -w;}
					else t += "P";
					const stat = {
						aggressiveP: "STR",
						aggressiveN: "INT",
						headstrongP: "CON",
						headstrongN: "WIS",
						braveP: "CHA",
						braveN: "DEX",
					}[t] || "INT";
					weights[stat] += w;
				}
				//TODO: If a stat is too high, exclude it (zero out its chance), unless all stats are high
				const stat = weighted_random(weights);
				++gamestate.stats[stat];
			}
			save_game();
		}
	}
	repaint();
}

function repaint() {
	//Once all game ticks have been processed, update the display.
	//Calculate the traits for display. Traits themselves could be positive
	//or negative (but if zero, will not be shown at all), and can be any
	//value; for display, we normalize them so all traits are positive
	//(using counterpart names ie -0.25 Brave becomes +0.25 Cowardly), and
	//the strongest trait is 1.0, with all others scaled accordingly.
	//However, if all your traits are close to zero, scale to 1.0 so that
	//the display indicates room for the traits to grow and shift.
	//Or should it be scaled so the (absolute) sum of all traits is 1.0?
	let scale = 1.0, traits = [];
	for (let tr of trait_display_order) {
		const t = gamestate.traits[tr]; if (!t) continue;
		traits.push(trait_labels[tr + (t < 0 ? "N" : "P")]);
		const abs = t < 0 ? -t : t;
		traits.push(abs);
		//scale += abs; //To scale to the sum
		if (scale < abs) scale = abs; //To scale to the largest
	}
	let path = gamestate.world.pathway;
	if (path.length > gamestate.world.location + 10) path = gamestate.world.pathway.slice(0, 10);
	const delay_proportion = gamestate.world.delay && gamestate.world.delay[0] / gamestate.world.delay[1];
	const current_action = gamestate.world.delay && DIV([ //"Current action" spinner. Absent if no action - should it be retained for display stability?
		SPAN({
			//Simple CSS spinner. The radial gradient specifies that, once we've reached the closest side, the rest is
			//the page background colour; this gives us a circle to work in, instead of filling out a square. Then the
			//actual spinner is defined by the conic gradient, giving a proportion in one colour and the rest in another.
			//In the center of the ring, we have the same lavender colour that makes up the background of the ring. Maybe
			//this should be #eee again? Unsure.
			style: `display: inline-block;
				width: 1.25em; height: 1.25em;
				background: radial-gradient(circle closest-side, lavender 50%, transparent 50% 100%, #eee 100%),
					conic-gradient(lavender 0 ${delay_proportion - .01}turn, rebeccapurple ${delay_proportion + .01}turn)
			`,
		}),
		" " + gamestate.world.delay[3],
	]);
	//Hitpoints graph. If you get below 75%, the browser should start showing it in
	//scarier colours, eg yellow or red, but I am not in control of that.
	const hpmeter = METER({
		style: "width: 100%",
		value: gamestate.stats.curhp,
		low: gamestate.stats.maxhp / 4,
		high: gamestate.stats.maxhp * 3 / 4,
		optimum: gamestate.stats.maxhp,
		max: gamestate.stats.maxhp,
	});
	replace_content("#display", [
		/*DIV({id: "controls", class: "buttonbox"}, [ //TODO: In debug mode, reenable this
			BUTTON({type: "button", id: "save"}, "Save game now"), "Game saves automatically on level up and death",
		]),*/
		//In gameplay mode, show a massively reduced top section - intended for inside OBS
		display_mode === "active" ? DIV([
			current_action || DIV([SPAN({style: "display: inline-block; height: 1.25em"}), "\xA0"]), //Ensure consistent height
			hpmeter,
		]) : DIV({id: "stats"}, [
			DIV(TWO_COL([
				//~ "Level", gamestate.stats.level,
				"Level", gamestate.stats.level + " (" + gamestate.world.baselevel + ")", //DEBUG: Show the base level
				//"Next", ""+(gamestate.stats.nextlevel - gamestate.stats.xp), //DEBUG: Numeric display of TNL
				undefined, METER({
					value: gamestate.stats.xp - gamestate.stats.prevlevel,
					max: gamestate.stats.nextlevel - gamestate.stats.prevlevel,
				}),
				"", "\xA0", //Shim
				"Sword", gamestate.equipment.sword,
				gamestate.equipment.bow && "Bow", gamestate.equipment.bow || "\xA0", //Hide the bow altogether if it hasn't yet been unlocked
				"Armor", gamestate.equipment.armor,
			])),
			DIV(TABLE({class: "twocol"}, [
				stat_display_order.map(stat => TR([
					TH(stat),
					TD({class: buff_color(stat_buff[stat])}, gamestate.stats[stat]),
				]))
			])),
			DIV(TWO_COL(traits.map(t => typeof t === "string" ? t : METER({value: t / scale})))),
			DIV({id: "messages"}, [
				messages.map(m => DIV(m)),
				display_mode === "active+status" && [current_action, hpmeter],
			]),
			allow_trait_requests ? DIV(TABLE([
				CAPTION("Next respawn, prefer:"),
				trait_display_order.map(t => gamestate.traits[t] && TR([
					TD(BUTTON({"data-traitrequest": t + "N"}, [trait_labels[t + "N"], " (" + (gamestate.requests[t + "N"]||0) + ")"])),
					TD(BUTTON({"data-traitrequest": t + "P"}, [trait_labels[t + "P"], " (" + (gamestate.requests[t + "P"]||0) + ")"])),
				])),
			])) : DIV([
				BUTTON({class: "twitchlogin", type: "button"}, "Log in to suggest traits"),
			]),
		]),
		DIV({id: "pathway"}, path.map((enc, idx) => DIV(
			{style: "background: " + pathway_background(idx - gamestate.world.location, enc)},
			encounter[enc.type].render(enc)
		)).reverse()),
	]);
	const msgs = DOM("#messages"); if (msgs) msgs.scroll(0, 9999); //Keep the messages showing the newest
}

export function render(data) {
	if (!ticking && data.gamestate) {
		gamestate = data.gamestate;
		//Update game state. If older data is loaded (or null data), this is the place to update it and
		//initialize any subsystems that need to be.
		if (!gamestate.stats) gamestate.stats = {STR:1, DEX:1, CON:1, INT:1, WIS:1, CHA:1, level: 1, xp: 0, gold: 0, dr: 0};
		if (!gamestate.stats.gold) gamestate.stats.gold = 0;
		if (!gamestate.stats.dr) gamestate.stats.dr = 0;
		if (!gamestate.traits) gamestate.traits = {aggressive: 0.1};
		if (!gamestate.equipment) gamestate.equipment = {sword: 1, armor: 1};
		if (!gamestate.world) gamestate.world = {baselevel: 1, blfrac: 0, pathway: [encounter.respawn.create()], location: 0, direction: "advancing"};
		if (!gamestate.world.direction) gamestate.world.direction = "advancing";
		if (!gamestate.world.blfrac) gamestate.world.blfrac = 0;
		if (!gamestate.requests) gamestate.requests = { };
		if (!gamestate.bosses) gamestate.bosses = { };
		if (!gamestate.buffs) gamestate.buffs = [];
		decay_buffs(0);
		gamestate.world.pathway.forEach(enc => {if (!enc.distance) enc.distance = 10; if (!enc.progress) enc.progress = 0;});
		recalc_next_boss();
		recalc_max_hp();
		basetime = performance.now();
		//In status-only mode, we never start ticking, and will always accept game state from the server.
		//In active gameplay mode (including active+status), we start ticking from the first state update,
		//and then maintain our own state internally, pushing back to the server periodically (which will
		//be ignored if we're on the demo channel).
		if (display_mode === "status") repaint();
		else ticking = setInterval(gametick, TICK_LENGTH);
	}
	if (data.requests) {gamestate.requests = data.requests; repaint();}
	//Signals other than game state will be things like "viewer-sponsored gift" or "trait requested".
}

on("click", "[data-traitrequest]", e => {
	//NOTE: This currently does not immediately update the local display in any way.
	//It may be nice to have faster feedback, though the number won't necessarily update.
	ws_sync.send({cmd: "traitrequest", trait: e.match.dataset.traitrequest});
});

//TODO: Call this automatically periodically, not too often but often enough.
//On levelup and on death may not be sufficient.
function save_game() {
	ws_sync.send({cmd: "save_game", gamestate});
}
on("click", "#save", save_game);

on("dragstart", "#browsersource", e => {
	const url = e.match.href + "&layer-name=Respawn%20Technician&layer-width=1920&layer-height=120";
	e.dataTransfer.setData("text/uri-list", url);
});
