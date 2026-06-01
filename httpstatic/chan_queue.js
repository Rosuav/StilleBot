import {lindt, replace_content, on} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DETAILS, FORM, H2, INPUT, LABEL, LI, P, SUMMARY, TABLE, TBODY, TD, TEXTAREA, TH, THEAD, TR, UL} = lindt; //autoimport
import {simpleconfirm, simplemessage} from "$$static||utils.js$$";

export function render(data) {
	if (minimode === 2) replace_content("#queueinfo", [
		TABLE([
			//TODO: Make the labels "Song" and "Musical/Artist" configurable
			THEAD(TR([TH("#"), TH("Song"), TH("Musical/Artist"), TH("Requestor"), TH()])),
			TBODY(!data.queue?.length ? TR(TD({colSpan: 5}, "No requests currently."))
			: data.queue.map((q, idx) => TR([
				TD(idx + 1),
				TD(q.title), //FIXME: Split into two cells
				TD(""),
				TD(q.user),
				TD((is_mod || q.user === myname) && BUTTON({class: "unchoose", "data-index": idx}, "X")),
			]))),
		]),
	]);
	else replace_content("#queueinfo", [
		H2("Requests"),
		!data.queue?.length ? P("No requests currently.")
			: UL(data.queue.map((q, idx) => LI([
				q.title, " [", q.user, "] ",
				(is_mod || q.user === myname) && BUTTON({class: "unchoose", "data-index": idx}, "Remove"),
			]))),
		!minimode && H2("Selections"),
		!minimode && data.selections && UL(data.selections.map(sel => 
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

const selfadd = simpleconfirm("Add this to the queue?", e => {
	ws_sync.send({cmd: "choose", selection: e.match.closest_data("selection")});
});
on("click", ".choose", e => {
	if (e.shiftKey) {
		DOM("#cf_selection").value = e.match.closest_data("selection");
		DOM("#cf_username").value = "";
		DOM("#choosefordlg").showModal();
	} else selfadd(e);
});
on("click", "#choosefor", e => {
	ws_sync.send({cmd: "choose", selection: DOM("#cf_selection").value, added_for: DOM("#cf_username").value});
});
export function sockmsg_choose(msg) {
	if (msg.error) simplemessage(msg.error, "Unable to add to the queue");
	else {
		//If it's successfully added, put a banner that fades out
		set_content("#flashed-message", "Added to queue: " + msg.selection).classList.add("visible");
		setTimeout(() => DOM("#flashed-message").classList.remove("visible"), 5000);
	}
}

on("click", ".unchoose", simpleconfirm("Remove this from the queue?", e => {
	ws_sync.send({cmd: "unchoose", index: +e.match.dataset.index});
}));

on("click", "#editselections", simpleconfirm("Replace the available selections?", e => {
	ws_sync.send({cmd: "configure", selections: DOM("#newselections").value.split("\n")});
}));

//NOTE: Limit can be set as a string or a number, but to set it to zero, must use "0".
on("change", "#queuelimit", e => ws_sync.send({cmd: "configure", queuelimit: e.match.value}));
