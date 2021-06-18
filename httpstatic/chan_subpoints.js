import choc, {set_content, DOM, on, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, DETAILS, SUMMARY, DIV, FORM, FIELDSET, LEGEND, LABEL, INPUT, TEXTAREA, OPTION, OPTGROUP, SELECT, TABLE, TR, TH, TD} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: "formless"});
import {waitlate} from "$$static||utils.js$$";

export const render_parent = DOM("#trackers tbody");
export function render_item(msg, obj) {
	if (!msg) return 0;
	return TR({"data-id": msg.id}, [
		//Unpaid | Font | Goal | Options | Actions | Link
		TD(INPUT({name: "unpaidpoints", type: "number", value: msg.unpaidpoints || 0})),
		TD([
			INPUT({name: "font", value: msg.font}),
			INPUT({name: "fontsize", type: "number", value: msg.fontsize || 0}),
		]),
		TD(INPUT({name: "goal", type: "number", value: msg.goal || 0})),
		TD([
			LABEL([INPUT({name: "usecomfy", type: "checkbox"}), "Use chat notifications"]),
		]),
		TD([
			BUTTON({type: "button", className: "savebtn"}, "Save"),
			BUTTON({type: "button", className: "deletebtn", "data-nonce": nonce}, "Delete?"),
		]),
		TD(A({className: "monitorlink", href: "subpoints?view=" + nonce}, "Drag me to OBS")),
	]);
}
export function render_empty() {
	render_parent.appendChild(TR([
		TD({colSpan: 6}, "No subpoint counters active. Create one!"),
	]));
}
export function render(data) { }

on("click", "#add_text", e => {
	ws_sync.send({cmd: "create"});
});

on("click", ".savebtn", e => {
	const tr = e.match.closest("tr");
	const msg = {cmd: "save", id: tr.dataset.id};
	tr.querySelectorAll("input").forEach(inp => msg[inp.name] = inp.value);
	console.log("Will save:", body);
});

on("click", ".deletebtn", waitlate(1000, 7500, "Really delete?", e => {
	ws_sync.send({cmd: "delete", id: e.match.closest("tr").dataset.id});
}));

on("dragstart", ".monitorlink", e => {
	const url = `${e.match.href}&layer-name=StilleBot%20subpoint%20counter&layer-width=200&layer-height=120`;
	e.dataTransfer.setData("text/uri-list", url);
});
