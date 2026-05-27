import {lindt, replace_content, on} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DETAILS, FORM, H2, LABEL, LI, P, SUMMARY, TEXTAREA, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

export function render(data) {
	replace_content("#queueinfo", [
		H2("Requests"),
		!data.queue?.length ? P("No requests currently.")
			: UL(data.queue.map(q => LI([
				"(queue entry)",
			]))),
		H2("Selections"),
		data.selections && UL(data.selections.map(LI([
			"(available selection)",
		]))),
		is_mod && DETAILS([
			SUMMARY("Moderator controls"),
			data.queue_open ? P([
				"The queue is open and people can make selections! ",
				BUTTON({type: "button", id: "closequeue"}, "Close queue"),
			]) : P([
				"The queue is closed. ",
				BUTTON({type: "button", id: "openqueue"}, "Open queue"),
			]),
			FORM([
				LABEL(["Add new selections, one per line:", BR(), TEXTAREA({id: "newselections", rows: 8, cols: 80})]),
				BR(), BUTTON({type: "button", id: "addselections"}, "Add"),
			]),
		]),
	]);
}

//No confirmation here; if you misclick, click it again.
on("click", "#openqueue", e => ws_sync.send({cmd: "configure", open: 1}));
on("click", "#closequeue", e => ws_sync.send({cmd: "configure", closed: 1}));

on("click", ".choose", simpleconfirm("Add this to the queue?", e => {
	ws_sync.send({cmd: "choose", selection: e.match.closest_data("selection")});
}));

on("click", "#addselections", simpleconfirm("Add this to the available selections?", e => {
	ws_sync.send({cmd: "newselection", selections: DOM("#newselections").value});
}));
