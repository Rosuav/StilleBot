import {lindt, replace_content, set_content, on} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, CAPTION, DETAILS, DIV, FORM, H1, H2, IMG, INPUT, LABEL, LI, P, SPAN, SUMMARY, TABLE, TBODY, TD, TEXTAREA, TH, THEAD, TR, UL} = lindt; //autoimport
import {simpleconfirm, simplemessage, TEXTFORMATTING, ensure_font} from "$$static||utils.js$$";

export function render(data) {
	if (minimode === 2) {
		const sty = data.panelstyle || { };
		if (sty.font) ensure_font(sty.font);
		document.body.style.background = sty.bgcolor;
		const btnstyle = "font-family: " + sty.font + ", " + sty.fontfamily + "; font-size: " + sty.fontsize + "px; color: " + sty.queuetextcolor + "; background: ";
		replace_content("#queueinfo", [
			myname === "-" && [H1({style: "color: aliceblue"}, "Not logged in"), H2(BUTTON({class: "twitchlogin"}, "Log in"))],
			TABLE({style: sty.css_text + "; margin-bottom: 5em"}, [
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
				data.close_after && Array(data.close_after).fill(1).map((one, idx) => TR({style: "background: " + ((idx&1) && sty.altrowcolor || sty.bgcolor)}, [
					TD(data.queue.length + idx + 1),
					TD({colSpan: 4}, "\xa0"),
				])),
			]),
			DIV({id: "bottombar"},
				data.queue_open ? SPAN({style: sty.css_text}, [
					BUTTON({type: "button", id: "closequeue", style: btnstyle + (sty.queuebgclose||"aliceblue")}, "Close Queue"),
					LABEL([SPAN({style: "padding: 0 0.75em"}, " after "), INPUT({id: "closeafter", type: "number", value: data.close_after || "0"})]),
				]) : BUTTON({type: "button", id: "openqueue", style: btnstyle + (sty.queuebgopen||"aliceblue")}, "Open Queue"),
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
		data.close_after && UL(Array(data.close_after).fill(1).map((one, idx) => LI("- open -"))),
		!minimode && H2("Selections"),
		!minimode && data.selections && UL(data.selections.map(sel =>
			//NOTE: The "Pick" button is secretly a login button if you're not logged in. That
			//way, rather than "log in, now you can see buttons to pick", it's "pick, but hey,
			//please log in". However, we don't automatically pick after the login is done.
			sel.title ? LI({"data-selection": sel.title}, [
				BUTTON({class: myname === "-" ? "twitchlogin" : "choose"}, "Pick"), " ",
				sel.title, " ",
				//TODO: Get a free "New!" icon that looks good
				sel.is_new && IMG({class: "is_new", src: "https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_6699625e38c847e5be28270aecffbd4b/default/light/1.0"}),
			])
			: sel.heading ? LI({class: "heading level" + (sel.level||1)}, sel.heading)
			: LI({class: "blank"}),
		)),
		is_mod && DETAILS([
			SUMMARY("Moderator controls"),
			P("Shift-pick a song if it's for someone else - you can enter the selector's name."),
			data.queue_open ? P([
				"The queue is open and people can make selections! ",
				BUTTON({type: "button", id: "closequeue"}, "Close queue"),
				LABEL([" after the next ", INPUT({id: "closeafter", type: "number", value: data.close_after || "0"}), " requests"]),
			]) : P([
				"The queue is closed. ",
				BUTTON({type: "button", id: "openqueue"}, "Open queue"),
			]),
			TABLE([
				CAPTION("When queue is opened or closed, put the following message in chat:"),
				TR([TH("Opened"), TD(INPUT({class: "autosave", "data-key": "openmsg", size: 80, value: data.openmsg}))]),
				TR([TH("Closed"), TD(INPUT({class: "autosave", "data-key": "closemsg", size: 80, value: data.closemsg}))]),
			]),
			P(BUTTON({class: "opendlg", "data-dlg": "panelcfgdlg"}, "Configure panel view")),
			FORM([
				LABEL(["Available selections:", BR(), TEXTAREA({id: "newselections", rows: 20, cols: 60,
					value: (data.selections||[]).map(sel =>
						sel.title ? sel.title + (sel.is_new ? " [New]" : "")
						: sel.heading ? "#".repeat(sel.level || 1) + " " + sel.heading : ""
					).join("\n") + "\n",
				})]),
				BR(), "TIP: Headings start with one or more # signs and [New] marks recent additions.",
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
on("click", "#closequeue", e => {
	const after = +DOM("#closeafter").value;
	if (after) ws_sync.send({cmd: "configure", closeafter: after});
	else ws_sync.send({cmd: "configure", closed: 1});
});

on("change", ".autosave", e => ws_sync.send({cmd: "configure", [e.match.dataset.key]: e.match.value}));

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
