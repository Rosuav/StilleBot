import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {TR, TD} = choc;
import {render_command, sockmsg_validated} from "$$static||command_editor.js$$";
export {sockmsg_validated};

export const render_parent = DOM("#triggers tbody");
export const render_item = render_command;
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 3}, "No triggers defined. Create one!"),
	]));
}
export function render(data) { }
