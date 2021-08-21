import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {CODE, BR, TR, TD, SPAN, DIV, UL, LI, INPUT} = choc;
import {render_item as render_command, add_hook, open_advanced_view, sockmsg_validated, sockmsg_loadfavs, favcheck} from "$$static||chan_commands.js$$";

export {sockmsg_validated, sockmsg_loadfavs};
export const render_parent = DOM("#triggers tbody");
export const render_item = render_command;
export function render_empty() {
	render_parent.appendChild(TR([
		TD({colSpan: 3}, "No triggers defined. Create one!"),
	]));
}
export function render(data) {favcheck();}
