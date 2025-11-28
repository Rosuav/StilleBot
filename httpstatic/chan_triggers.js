import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {CODE, TD, TR} = choc; //autoimport
import {render_command, cmd_configure, open_advanced_view} from "$$static||command_editor.js$$";

ws_sync.send({cmd: "subscribe", type: "cmdedit", group: "!!trigger"});

export const render_parent = DOM("#triggers tbody");
export function render_item(el, prev) {
	return render_command(el, prev,
		el.expr2 === "{username}" ? "When " + el.expr1 + " speaks..." :
		el.expr2 === "{rewardid}" ? "When a reward is redeemed..." :
		el.conditional === "contains" || el.conditional === "string" ? (
			el.expr1 ? ["When ", CODE(el.expr1), " is typed... "] : "Custom trigger... "
		) : ["When a msg matches ", CODE(el.expr1 || ""), " ... "],
	);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 3}, "No triggers defined. Create one!"),
	]));
}
export function render(data) { }

on("click", "#addtrigger", e => open_advanced_view({id: "", template: true,
	"casefold": "on",
	"conditional": "contains",
	"expr1": "hello", "expr2": "%s",
	"message": "Hello to you too!!",
}));
