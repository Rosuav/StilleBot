import {lindt, replace_content, on} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DETAILS, FORM, H2, LABEL, LI, P, SUMMARY, TEXTAREA, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

export function render(data) {
	replace_content("#queueinfo", [
		H2("Requests"),
		!data.queue.length ? P("No requests currently.")
			: UL(data.queue.map(q => LI([
				"(queue entry)",
			]))),
		H2("Selections"),
		data.config.selections && UL(data.config.selections.map(LI([
			"(available selection)",
		]))),
		is_mod && DETAILS([
			SUMMARY("Moderator controls"),
			BUTTON({type: "button", id: "openclose"}, data.config.queue_open ? "Close queue" : "Open queue"),
			FORM([
				LABEL(["Add new selections, one per line:", BR(), TEXTAREA({id: "newselections", rows: 8, cols: 80})]),
				BR(), BUTTON({type: "button", id: "addselections"}, "Add"),
			]),
		]),
	]);
}

//No confirmation here; if you misclick, click it again.
on("click", "#openclose", e => ws_sync.send({cmd: "configure", toggleopen: 1}));

on("click", ".choose", simpleconfirm("Add this to the queue?", e => {
	ws_sync.send({cmd: "choose", selection: e.match.closest_data("selection")});
}));

on("click", "#addselections", simpleconfirm("Add this to the available selections?", e => {
	ws_sync.send({cmd: "newselection", selections: DOM("#newselections").value});
}));
