import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {} = lindt; //autoimport

const TICK_LENGTH = 100;
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
	}
}

export function render(data) {
	if (!ticking) {basetime = performance.now(); ticking = setInterval(gametick, TICK_LENGTH);}
}
