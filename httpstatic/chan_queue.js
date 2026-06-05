import {lindt, replace_content, set_content, on} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DETAILS, DIV, FORM, H2, INPUT, LABEL, LI, P, SUMMARY, TABLE, TBODY, TD, TEXTAREA, TH, THEAD, TR, UL} = lindt; //autoimport
import {simpleconfirm, simplemessage, TEXTFORMATTING, ensure_font} from "$$static||utils.js$$";

export function render(data) {
	if (minimode === 2) {
		const sty = data.panelstyle || { };
		if (sty.font) ensure_font(sty.font);
		document.body.style.background = sty.bgcolor;
		const btnstyle = "font-family: " + sty.font + ", " + sty.fontfamily + "; font-size: " + sty.fontsize + "px; color: " + sty.queuetextcolor + "; background: ";
		replace_content("#queueinfo", [
			TABLE({style: sty.css_text}, [
				THEAD(TR({style: "background: " + (sty.altrowcolor || sty.bgcolor)}, [TH("#"), TH(sty.itemlbl || "Song"), TH(sty.originlbl || "Musical/Artist"), TH("Requestor"), TH()])),
				TBODY(!data.queue?.length ? TR(TD({colSpan: 5}, "No requests currently."))
				: data.queue.map((q, idx) => {
					const m = /([^(]+) \(([^)]+)\)/.exec(q.title);
					const item = m ? m[1] : q.title, origin = m ? m[2] : sty.dfltorigin || "";
					return TR({style: "background: " + ((idx&1) && sty.altrowcolor || sty.bgcolor)}, [
						TD(idx + 1),
						TD(item),
						TD(origin),
						TD(q.user),
						TD((is_mod || q.user === myname) && BUTTON({class: "unchoose", "data-index": idx}, "\u274C")),
					]);
				})),
			]),
			DIV({id: "bottombar"},
				data.queue_open ? BUTTON({type: "button", id: "closequeue", style: btnstyle + (sty.queuebgclose||"aliceblue")}, "Close Queue")
					: BUTTON({type: "button", id: "openqueue", style: btnstyle + (sty.queuebgopen||"aliceblue")}, "Open Queue"),
			),
		]);
	}
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
			P(BUTTON({class: "opendlg", "data-dlg": "panelcfgdlg"}, "Configure panel view")),
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
	if (is_mod && data.panelstyle) for (let attr in data.panelstyle) {
		const elem = DOM("#panelconfigs [name=" + attr + "]");
		if (elem) elem.value = data.panelstyle[attr] || "";
	}
}

//Don't bother if you're not a mod, you won't be able to save it anyway
if (is_mod && !minimode) set_content("#panelconfigs", [
	TEXTFORMATTING({
		texts: [
			{name: "itemlbl", label: "Item heading", desc: " The thing people select"},
			{name: "originlbl", label: "Origin heading", desc: " Extra info in parentheses after the selection"},
			{name: "dfltorigin", label: "Default origin", desc: " If there's no origin, use this"},
		],
		colors: [
			{name: "altrowcolor", label: "Even rows", suffix: " Alternating rows of the queue use this or the default"},
			{name: "queuetextcolor", label: "Open/Close Queue", suffix: " Text color for the Open/Close Queue button"},
			{name: "queuebgopen", label: "Open button", suffix: " Background color for Open Queue"},
			{name: "queuebgclose", label: "Close button", suffix: " Background color for Close Queue"},
		],
	}),
]);

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

on("click", "#panelcfgsave", e => {
	const sty = { };
	for (let el of DOM("#panelcfgdlg form").elements)
		if (el.name) sty[el.name] = el.value;
	ws_sync.send({cmd: "configure", panelstyle: sty});
});
