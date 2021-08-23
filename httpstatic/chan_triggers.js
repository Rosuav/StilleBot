import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {CODE, BR, TR, TD, SPAN, DIV, UL, LI, INPUT} = choc;
import {render_item, sockmsg_validated, sockmsg_loadfavs, favcheck} from "$$static||chan_commands.js$$";
export {render_item, sockmsg_validated, sockmsg_loadfavs};

export const render_parent = DOM("#triggers tbody");
export function render_empty() {
	render_parent.appendChild(TR([
		TD({colSpan: 3}, "No triggers defined. Create one!"),
	]));
}
export function render(data) {favcheck();}
