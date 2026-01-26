import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, DIV, TABLE, TD, TH, TR} = lindt; //autoimport

let gamestate = { };

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
			])),
			DIV(TABLE({class: "twocol"}, [
				["STR", "DEX", "CON", "INT", "WIS", "CHA"].map(stat => TR([
					TH(stat),
					TD(gamestate.stats[stat]),
				]))
			])),
		]),
		DIV({id: "pathway"}, [
			DIV("Tile behind us"),
			DIV("Current tile"),
			DIV("Tile ahead of us"),
		]),
	]);
}

export function render(data) {
	if (!ticking && data.gamestate) {
		gamestate = data.gamestate;
		//Update game state. If older data is loaded (or null data), this is the place to update it and
		//initialize any subsystems that need to be.
		if (!gamestate.stats) gamestate.stats = {STR:1, DEX:1, CON:1, INT:1, WIS:1, CHA:1, level: 1, xp: 0};
		if (!gamestate.traits) gamestate.traits = {aggressive: 0.1};
		if (!gamestate.equipment) gamestate.equipment = {sword: 1, bow: 1, armor: 1};
		if (!gamestate.world) gamestate.world = {baselevel: 1, pathway: []};
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
