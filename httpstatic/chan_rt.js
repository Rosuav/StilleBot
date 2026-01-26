import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, DIV, TABLE, TD, TH, TR} = lindt; //autoimport

let gamestate = { };

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
	respawn(state) {
		console.log("Spawning a respawner");
		//Respawner states:
		//unreached - new, hasn't yet been tagged
		//reached - has been activated, but isn't current
		//current - where the Hero will respawn
		//When a respawner becomes current, any existing current respawner becomes Reached.
		return {type: "respawn", state: state || "unreached"};
	},
	clear() {return {type: "clear"};},
	enemy() {return {type: "enemy", level: spawnlevel()};},
	//boss should be handled differently, and will require a hard-coded list of bosses
	equipment() {return {type: "equipment", slot: "unknown", level: spawnlevel()};}, //Slot becomes known when the item is collected
	//item() {return {type: "item"};}, //Not sure how to do these yet
	//branch() {console.error("IMPLEMENT ME");},
};
const encounter_action = {
	respawn(loc) {
		if (loc.state !== "current") loc.state = "current"; //TODO: And set all other currents to "reached"
		gamestate.world.direction = "advancing"; //Once you run back as far as a respawner, there's no reason to keep retreating.
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
	for (let i = 0; i < elements.length; i += 2)
		rows.push(TR([TH(elements[i]), TD(elements[i+1])]));
	return TABLE({class: "twocol"}, rows);
}

const TICK_LENGTH = 1000; //FIXME: For normal operation, a tick should be 100ms
const MAX_PATHWAY_LENGTH = 20; //Ideally this should be more than can be seen on any reasonable screen

function populate() {
	//First, populate the world. We need to have enough behind us to draw, our current
	//location, and three cells ahead of us.
	while (gamestate.world.location >= gamestate.world.pathway.length - 3) {
		//Choose an encounter type.
		//TODO: Dynamically adjust these weights according to circumstances;
		//for example, be generous with equipment if all items are subpar, or
		//offer more enemies if you have good gear.
		let distance_to_respawn = 1000;
		for (let enc of gamestate.world.pathway) {
			++distance_to_respawn;
			if (enc.type === "respawn") distance_to_respawn = 0;
		}
		const weights = {
			//Respawners become more likely as you get further from one,
			//and (not shown here) guaranteed to spawn once you're too far.
			respawn: distance_to_respawn < 8 ? 0 : distance_to_respawn,
			clear: 10,
			enemy: 15,
			equipment: 2,
			//item: 2,
			//boss: 3, //Zero this out if there is no undefeated boss at/below base level, or if there's any boss on screen (including a defeated one)
			//branch: 4, //BIG OL' TODO RIGHT THERE
		};
		let enctype;
		//First, are there any guaranteed spawn demands?
		if (distance_to_respawn >= 15) enctype = "respawn"; //NOTE: This figure includes the 3-square advancement
		//else if (there's a user-provided item spawn requested) enctype = "item";
		//Otherwise, weighted random
		else {
			let totweight = 0;
			for (let w of Object.values(weights)) totweight += w;
			let selection = Math.random() * totweight; //Yes, this isn't 100% perfect, but it's close enough
			for (let [t, w] of Object.entries(weights)) if ((selection -= w) < 0) {enctype = t; break;}
		}
		if (!enctype || !encounter[enctype]) break; //Shouldn't happen - for some reason nothing can spawn.
		console.log("ADDING", enctype);
		const enc = encounter[enctype]();
		if (!enc.distance) enc.distance = Math.max(Math.floor(Math.random() * spawnlevel()), 10); //Distances tend to increase as the game progresses
		enc.progress = 0;
		if (gamestate.world.pathway.push(enc) > MAX_PATHWAY_LENGTH) {
			gamestate.world.pathway.shift(); //Discard the oldest
			--gamestate.world.location;
		}
	}
}

//NOTE: The game tick is not started until we first receive status from the server, but
//after that, it will continue to run.
let ticking = null, basetime, curtick = 0;
function gametick() {
	const nowtick = (performance.now() - basetime) / TICK_LENGTH; //Note that this may be fractional
	//Whenever this function is called, update game state for all ticks that have happened
	//between lastticktime and now. If the page lags out, we should still be able to do all
	//game ticks (albeit delayed), so we'll catch up before trying to render.
	while (curtick < nowtick) {
		++curtick;
		console.log("Tick ", curtick);
		populate();

		//Take a step!
		//Does the current location demand more action? Time delays are counted in ticks.
		const location = gamestate.world.pathway[gamestate.world.location];
		const handler = encounter_action[location.type]; if (handler) handler(location);
		//The handler may have changed state. The last step is always to move, either advance or retreat.
		if (gamestate.world.direction === "advancing") {
			if (++location.progress >= location.distance) {++gamestate.world.location; populate();}
		} else {
			if (--location.progress <= 0) --gamestate.world.location;
		}
		console.log("At", location.progress + "/" + location.distance, location);
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
			}
		}
	}
	//Once all game ticks have been processed, update the display.
	replace_content("#display", [
		DIV({id: "controls", class: "buttonbox"}, [
			BUTTON({type: "button", id: "save"}, "Save game now"), "Game saves automatically on level up and death",
		]),
		DIV({id: "stats"}, [
			DIV(TWO_COL([
				"Level", gamestate.stats.level,
				"Next", ""+(gamestate.stats.nextlevel - gamestate.stats.xp),
				"\xa0", "",
				"Sword", gamestate.equipment.sword,
				"Bow", gamestate.equipment.bow,
				"Armor", gamestate.equipment.armor,
			])),
			DIV(TABLE({class: "twocol"}, [
				["STR", "DEX", "CON", "INT", "WIS", "CHA"].map(stat => TR([
					TH(stat),
					TD(gamestate.stats[stat]),
				]))
			])),
		]),
		DIV({id: "pathway"}, gamestate.world.pathway.map((enc, idx) => DIV([
			idx === gamestate.world.location && ">",
			enc.type,
		])).reverse()),
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
		if (!gamestate.world) gamestate.world = {baselevel: 1, pathway: [encounter.respawn("current")], location: 0};
		if (!gamestate.world.direction) gamestate.world.direction = "advancing";
		gamestate.world.pathway.forEach(enc => {if (!enc.distance) enc.distance = 10; if (!enc.progress) enc.progress = 0;});
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
