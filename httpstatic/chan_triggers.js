import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {CODE, TD, TR} = choc; //autoimport
import {render_command, cmd_configure, sockmsg_validated, sockmsg_changetab_failed} from "$$static||command_editor.js$$";
export {sockmsg_validated, sockmsg_changetab_failed};

export const render_parent = DOM("#triggers tbody");
export function render_item(el, prev) {
	return render_command(el, prev,
		el.conditional === "contains" ?
			["When ", CODE(el.expr1), " is typed..."]
		: ["When a msg matches ", CODE(el.expr1 || ""), " ..."],
	);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 3}, "No triggers defined. Create one!"),
	]));
}
export function render(data) { }
