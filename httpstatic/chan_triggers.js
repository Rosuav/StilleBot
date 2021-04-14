import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {CODE, BR, TR, TD, SPAN, DIV, UL, LI, INPUT} = choc;
import {render_item as render_command, add_hook, open_advanced_view} from "$$static||chan_commands.js$$";

export const render_parent = DOM("#triggers tbody");
export function render_item(msg) {
	console.log(msg)
	//TODO: Hide the "otherwise" and render it regardless. That way, tabular view
	//still has value, although you can't change the trigger conditions.
	return render_command(msg);
}
export function render_empty() {
	render_parent.appendChild(TR([
		TD({colSpan: 3}, "No triggers defined. Create one!"),
	]));
}
export function render(data) { }
