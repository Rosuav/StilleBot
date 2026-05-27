import {lindt, replace_content, on} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DETAILS, FORM, H2, INPUT, LABEL, LI, P, SUMMARY, TEXTAREA, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

export function render(data) {
	replace_content("#queueinfo", [
		H2("Requests"),
		!data.queue?.length ? P("No requests currently.")
			: UL(data.queue.map((q, idx) => LI([
				q.title, " [", q.user, "] ",
				(is_mod || q.user === myname) && BUTTON({class: "unchoose", "data-index": idx}, "Remove"),
			]))),
		H2("Selections"),
		data.selections && UL(data.selections.map(sel => 
			sel.title ? LI({"data-selection": sel.title}, [BUTTON({class: "choose"}, "Pick"), " ", sel.title])
			: sel.heading ? LI({class: "heading"}, sel.heading)
			: LI({class: "blank"}),
		)),
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
				LABEL(["Available selections:", BR(), TEXTAREA({id: "newselections", rows: 20, cols: 60,
					value: (data.selections||[]).map(sel =>
						sel.title ? sel.title : sel.heading ? "# " + sel.heading : ""
					).join("\n") + "\n",
				})]),
				BR(), BUTTON({type: "button", id: "editselections"}, "Save"),
				P(LABEL(["Queue limit per person: ", INPUT({type: "number", id: "queuelimit", minimum: 0, value: data.queuelimit || 0})])),
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

on("click", ".unchoose", simpleconfirm("Remove this from the queue?", e => {
	ws_sync.send({cmd: "unchoose", index: +e.match.dataset.index});
}));

on("click", "#editselections", simpleconfirm("Replace the available selections?", e => {
	ws_sync.send({cmd: "configure", selections: DOM("#newselections").value.split("\n")});
}));

//NOTE: Limit can be set as a string or a number, but to set it to zero, must use "0".
on("change", "#queuelimit", e => ws_sync.send({cmd: "configure", queuelimit: e.match.value}));
