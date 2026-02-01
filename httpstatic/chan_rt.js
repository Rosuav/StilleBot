import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, DIV, METER, TABLE, TD, TH, TR} = lindt; //autoimport

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
const BASE_MONSTER_XP = 100;

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

function recalc_max_hp() {
	const maxhp = Math.ceil(10 * (1.04 ** gamestate.stats.level) * (1.05 ** gamestate.stats.CON));
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
	return Math.ceil(3 * (1.08 ** level) * (Math.random() * 0.5 + 0.75)); //Enemy hitpoints will be +/-25% of the basic calculation
}
function enemy_melee_damage(level) {
	return Math.ceil(
		(1.15 ** level)
		* (gamestate.world.baselevel / gamestate.equipment.armor) //Note that armor is functionally a damage reduction effect
		* (Math.random() * 0.6 + 0.70)
	);
}

function take_damage(dmg) {
	if (dmg >= gamestate.stats.curhp) {
		//You died, Mr Reynolds.
		//TODO: Reduce XP or add an XP gain penalty for a while
		msg("THE HERO DIED");
		//But hey, death isn't the end!
		gamestate.world.delay = [10, "::respawn"];
		gamestate.stats.curhp = 0;
		return;
	}
	msg("Ouch! " + dmg + " damage!");
	gamestate.stats.curhp -= dmg;
}

function respawn() {
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
	gamestate.world.delay = [5, "emerge"];
	gamestate.stats.curhp = gamestate.stats.maxhp;
	//TODO: Update traits.
}

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
Softcap not currently implemented as there are no bosses.
*/
function spawnlevel() {
	let level = gamestate.world.baselevel;
	let rand = Math.min(level/2, 10); //Spread by +/- 10 levels each way, but not more than half the base level
	level += Math.trunc(Math.random() * rand*2 - rand);
	//TODO: Softcap based on undefeated bosses
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
				msg("Activating respawn chamber");
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
				msg("Hero hits for " + dmg + "!"); //Won't eventually be needed
				loc.curhp -= dmg;
				loc.state = "enemyhit";
			} else {
				//Uh oh, here comes a blow in response!
				take_damage(enemy_melee_damage(loc.level)); //Might result in death.
				loc.state = "herohit";
			}
			return "hold";
		},
		desire: {aggressiveP: 10, headstrongP: 5, braveP: 5},
		render(loc) {
			if (loc.curhp) return "Enemy: " + loc.curhp + "/" + loc.maxhp;
			if (loc.maxhp) return "Corpse";
			return "Enemy";
		},
	},
	//boss should be handled differently, and will require a hard-coded list of bosses
	equipment: {
		create() {return {type: "equipment", slot: "unknown", level: spawnlevel() + 1};}, //Slot becomes known when the item is collected
		enter(loc) {
			if (loc.slot === "unknown") {
				//Not yet collected!
				loc.slot = random_choice(["sword", "bow", "armor"]);
				if (gamestate.equipment[loc.slot] < loc.level) {
					//It's an upgrade! Take some time to pick it up.
					gamestate.world.delay = [loc.slot === "armor" ? 10 : 5, "equip"];
					msg("Equipping a level " + loc.level + " " + loc.slot); //TODO: Word them differently
				} else msg("Bypassing a mere level " + loc.level + " " + loc.slot);
			}
		},
		equip(loc) {
			gamestate.equipment[loc.slot] = loc.level; //Done equipping it, let's go!
		},
		desire: {headstrongN: 10},
		render(loc) {
			if (loc.slot === "unknown") return "Equipment";
			return "L" + loc.level + " " + loc.slot;
		},
	},
	//item: {create() {return {type: "item"};}}, //Not sure how to do these yet
	branch: {
		create() {
			//A branch needs to have its own pathway in it. Note that its location gets a fixed value; this
			//makes the populate() function simpler, and has no other effect.
			const ret = {type: "branch", pathway: [], location: -1};
			populate(ret);
			return ret;
		},
		enter(loc) {
			msg("Contemplating which path to take...");
			gamestate.world.delay = [10, "pickpath"];
		},
		pickpath(loc) {
			//TODO: If retreating, do a bravery check to switch and stop retreating. This won't
			//require the ten-round delay.

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
			if (score1 > score2) {
				//To switch, we actually mutate both paths. However, we also flag the
				//branch so that we invert the display; the 2D view, when implemented,
				//will use this to know that the display should be flipped back to
				//compensate.
				loc.flipped = !loc.flipped;
				loc.pathway = gamestate.world.pathway.splice(gamestate.world.location+1, Infinity, ...loc.pathway);
			}
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

const TICK_LENGTH = 1000; //FIXME: For normal operation, a tick should be 100ms
const MAX_PATHWAY_LENGTH = 20; //Ideally this should be more than can be seen on any reasonable screen

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
			clear: 10,
			enemy: 15,
			equipment: 2,
			//item: 2,
			//boss: 3, //Zero this out if there is no undefeated boss at/below base level, or if there's any boss on screen (including a defeated one)
			branch: distance.branch < 3 ? 0 : distance.branch,
		};
		let enctype;
		//First, are there any guaranteed spawn demands?
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
	}
}

function change_encounter(dir) {
	gamestate.world.location += dir;
	populate(gamestate.world); //Check if we need to generate some more pathway. Won't be needed if dir is -1 but it doesn't hurt.
	//Does this need to become its own function, eg location_trigger("enter") ?
	const location = gamestate.world.pathway[gamestate.world.location];
	const handler = encounter[location.type].enter; if (handler) handler(location);
}
	
function pathway_background(pos, enc) {
	//Transition from future colour to past colour with a progress bar in the current encounter
	if (pos < 0) return "#88f";
	if (pos > 0) return "aliceblue";
	const progress = enc.progress * 100 / enc.distance;
	return "linear-gradient(to right, #88f, #88f " + progress + "%, aliceblue " + progress + "%, aliceblue)";
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
			if (!--gamestate.world.delay[0]) {
				//Delay is over. Call the callback.
				const cb = gamestate.world.delay[1];
				delete gamestate.world.delay;
				//Special-case the respawn delay; maybe will need others that are also global.
				if (cb === "::respawn") respawn();
				else {
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
		//TODO: If advancing and the next location has an enemy, chance to take a bow shot

		//Finally, check state-based updates.
		if (!gamestate.stats.nextlevel) gamestate.stats.nextlevel = tnl(gamestate.stats.level);
		//In the unlikely event that you one-shot more than one level's worth of XP, level up once
		//per tick at most. In fact, if there's any sort of animation for the level up effect, we
		//need to block further advancement until that animation is complete.
		if (gamestate.stats.xp >= gamestate.stats.nextlevel) {
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
		}
	}
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
	replace_content("#display", [
		DIV({id: "controls", class: "buttonbox"}, [ //TODO: Hide these if we're in overlay mode
			BUTTON({type: "button", id: "save"}, "Save game now"), "Game saves automatically on level up and death",
		]),
		DIV({id: "stats"}, [
			DIV(TWO_COL([
				"Level", gamestate.stats.level,
				"Next", ""+(gamestate.stats.nextlevel - gamestate.stats.xp),
				//Hitpoints graph. If you get below 75%, the browser should start showing it in
				//scarier colours, eg yellow or red, but I am not in control of that.
				undefined, METER({
					value: gamestate.stats.curhp,
					low: gamestate.stats.maxhp / 4,
					high: gamestate.stats.maxhp * 3 / 4,
					optimum: gamestate.stats.maxhp,
					max: gamestate.stats.maxhp,
				}),
				"Sword", gamestate.equipment.sword,
				"Bow", gamestate.equipment.bow,
				"Armor", gamestate.equipment.armor,
			])),
			DIV(TABLE({class: "twocol"}, [
				stat_display_order.map(stat => TR([
					TH(stat),
					TD(gamestate.stats[stat]),
				]))
			])),
			DIV(TWO_COL(traits.map(t => typeof t === "string" ? t : METER({value: t / scale})))),
			DIV({id: "messages"}, messages.map(m => DIV(m))),
		]),
		DIV({id: "pathway"}, path.map((enc, idx) => DIV(
			{style: "background: " + pathway_background(idx - gamestate.world.location, enc)},
			encounter[enc.type].render(enc)
		)).reverse()),
	]);
}

export function render(data) {
	if (!ticking && data.gamestate) {
		gamestate = data.gamestate;
		//Update game state. If older data is loaded (or null data), this is the place to update it and
		//initialize any subsystems that need to be.
		if (!gamestate.stats) gamestate.stats = {STR:1, DEX:1, CON:1, INT:1, WIS:1, CHA:1, level: 1, xp: 0};
		if (!gamestate.stats.gold) gamestate.stats.gold = 0;
		if (!gamestate.traits) gamestate.traits = {aggressive: 0.1};
		if (!gamestate.equipment) gamestate.equipment = {sword: 1, bow: 1, armor: 1};
		if (!gamestate.world) gamestate.world = {baselevel: 1, pathway: [encounter.respawn.create()], location: 0};
		if (!gamestate.world.direction) gamestate.world.direction = "advancing";
		gamestate.world.pathway.forEach(enc => {if (!enc.distance) enc.distance = 10; if (!enc.progress) enc.progress = 0;});
		recalc_max_hp();
		basetime = performance.now();
		ticking = setInterval(gametick, TICK_LENGTH);
	}
	//Signals other than game state will be things like "viewer-sponsored gift".
}

//TODO: Call this automatically periodically, not too often but often enough.
//On levelup and on death may not be sufficient.
function save_game() {
	ws_sync.send({cmd: "save_game", gamestate});
}
on("click", "#save", save_game);
