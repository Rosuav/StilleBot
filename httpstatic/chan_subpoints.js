import choc, {set_content, DOM, on, fix_dialogs} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, INPUT, LABEL, OPTION, SELECT, TD, TR} = choc; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

export const render_parent = DOM("#trackers tbody");
export function render_item(msg, obj) {
	if (!msg) return 0;
	return TR({"data-id": msg.id}, [
		TD(INPUT({name: "unpaidpoints", type: "number", value: msg.unpaidpoints || 0})),
		TD([
			INPUT({name: "font", value: msg.font || ""}),
			INPUT({name: "fontsize", type: "number", value: msg.fontsize || 18}),
		]),
		TD([
			INPUT({name: "goal", type: "number", value: msg.goal || 0}),
			SELECT({name: "goaltype", value: msg.goaltype || "points"}, [
				OPTION({value: "points"}, "points"),
				OPTION({value: "subs"}, "subs"),
				OPTION({value: "plus"}, "Plus points"),
			]),
		]),
		TD([
			LABEL([INPUT({name: "usecomfy", type: "checkbox", checked: msg.usecomfy}), "Use chat notifications"]),
		]),
		TD([
			BUTTON({type: "button", className: "savebtn"}, "Save"),
			BUTTON({type: "button", className: "deletebtn"}, "Delete?"),
		]),
		TD(A({className: "monitorlink", href: "subpoints?view=" + msg.id}, "Drag me to OBS")),
	]);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 6}, "No subpoint trackers active. Create one!"),
	]));
}
export function render(data) { }

on("click", "#add_tracker", e => {
	ws_sync.send({cmd: "create"});
});

on("click", ".savebtn", e => {
	const tr = e.match.closest("tr");
	const msg = {cmd: "save", id: tr.dataset.id};
	tr.querySelectorAll("input,select").forEach(inp => msg[inp.name] = inp.type === "checkbox" ? inp.checked : inp.value);
	ws_sync.send(msg);
});

on("click", ".deletebtn", simpleconfirm("Delete this monitor?", e => {
	ws_sync.send({cmd: "delete", id: e.match.closest("tr").dataset.id});
}));

on("dragstart", ".monitorlink", e => {
	const url = `${e.match.href}&layer-name=StilleBot%20subpoint%20tracker&layer-width=200&layer-height=120`;
	e.dataTransfer.setData("text/uri-list", url);
});
