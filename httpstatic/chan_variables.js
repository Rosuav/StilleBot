import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV, TR, TD, UL, LI, B, INPUT, TEXTAREA, BUTTON} = choc;
import {waitlate} from "$$static||utils.js$$";

export const render_parent = DOM("#variables tbody");
export function render_item(item) {
	return TR({"data-id": item.id}, [
		TD(item.id),
		TD(INPUT({className: "value", value: item.curval})),
		TD([BUTTON({type: "button", className: "setvalue"}, "Set value"), BUTTON({type: "button", className: "delete"}, "Delete")]),
		TD(UL(item.usage.map(u => LI([B(u.name), " " + u.action])))),
	]);
}
export function render_empty() {
	render_parent.appendChild(TR([
		TD({colSpan: 4}, "No variables found."),
	]));
}
export function render(data) { }

on("click", ".setvalue", e => {
	const tr = e.match.closest("tr");
	ws_sync.send({cmd: "update", id: tr.dataset.id, value: tr.querySelector(".value").value});
});

on("click", ".delete", waitlate(750, 5000, "Really delete?", e => {
	ws_sync.send({cmd: "delete", id: e.match.closest("tr").dataset.id});
}));
