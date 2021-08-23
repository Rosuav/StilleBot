import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {CODE, BR, TR, TD, SPAN, DIV, UL, LI, INPUT} = choc;
import {render_command, sockmsg_validated, sockmsg_loadfavs, favcheck} from "$$static||command_editor.js$$";
export {sockmsg_validated, sockmsg_loadfavs};
import "$$static||chan_commands.js$$"; //Deprecated

export const render_parent = DOM("#triggers tbody");
export const render_item = render_command;
export function render_empty() {
	render_parent.appendChild(TR([ //TODO: Ensure that this will be removed if we get a single-item render
		TD({colSpan: 3}, "No triggers defined. Create one!"),
	]));
}
export function render(data) {favcheck();}
