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
		TD({colSpan: 3}, "No triggers defined. Click Add to create one!"),
	]));
}
export function render(data) { }

on("click", "#addtrigger", e => {
	ws_sync.send({cmd: "update", cmdname: "", response: {
		message: "Response goes here",
		conditional: "contains",
		expr1: "Trigger word",
		expr2: "%s",
	}});
});
export function sockmsg_newtrigger(data) {
	console.log("Added successfully!", data);
	open_advanced_view(data.response);
}
//add_hook("open_advanced", cmd => set_content("#parameters", describe_all_params(command_lookup[cmd.id])));
//TODO: Hide the "otherwise" when advanced view is loaded up (but only at top level)
