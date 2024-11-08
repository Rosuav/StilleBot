import {choc, lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, DIV, IMG, INPUT, LABEL, LI, OPTION, P, PRE, SPAN, TD, TEXTAREA, TIME, TR, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

function format_time(ts) {
	if (!ts) return "";
	const t = new Date(ts * 1000);
	//TODO: Make an abbreviated form for the initial display
	//For anything today, just show the time. For something this week, "Thu 12:30".
	//For something older than that, just show the date.
	return TIME({datetime: t.toISOString(), title: t.toLocaleString()}, t.toLocaleString());
}

function format_timedelta(sec) {
	let desc = sec + " seconds ago";
	if (sec > 86400 * 2) desc = Math.floor(sec / 86400) + " days ago";
	else if (sec > 86400) desc = "yesterday";
	else if (sec > 7200) desc = Math.floor(sec / 3600) + " hours ago";
	else if (sec > 3600) desc = "an hour ago";
	else if (sec > 60) desc = Math.floor(sec / 60) + " minutes ago";
	return TIME({datetime: "P" + sec + "S"}, desc);
}

function format_user(u) {
	if (!u) return "";
	return [ //Should this be a link to the person's Twitch page?
		IMG({src: u.profile_image_url, alt: "(avatar)"}),
		u.display_name,
	];
}

export const autorender = {
	form_parent: DOM("#forms"),
	form(f) {return choc.LI({"data-id": f.id, class: "openform", ".form_data": f}, [
		f.id, " ", f.formtitle,
	]);},
	form_empty() {return DOM("#forms").appendChild(choc.LI([
		"No forms yet - create one!",
	]));},
}

const render_element = { //Matches _element_types (see Pike code)
	"": (el, lbl) => [ //Defaults that are used by the majority of elements //extcall
		P({class: "topmatter"}, [
			SPAN(lbl || "Unknown element type - something went wrong - " + el.type),
			LABEL([INPUT({type: "checkbox", name: "required", checked: !!el.required}), " Required"]),
		]),
		LABEL(["Description:", BR(), TEXTAREA({name: "text", value: el.text || "", rows: 2, cols: 80}), BR()]),
	],
	twitchid: el => [ //extcall
		render_element[""](el, "Twitch username"),
		LABEL([INPUT({type: "checkbox", name: "permitted_only", checked: !!el.permitted_only}), " Restrict to the permitted user (if applicable)"]),
		P(["When a form is granted to a specific user (via a command or trigger), requriring", BR(),
			"that specific user to be logged in will ensure that the form is not sniped."]),
	],
	simple: el => [ //extcall
		render_element[""](el, "Text input"),
		LABEL(["Label: ", INPUT({name: "label", value: el.label || ""}), " - shown in the form"]),
		//Type (numeric/text)?
	],
	url: el => [ //extcall
		render_element[""](el, "URL (web address)"),
		LABEL(["Label: ", INPUT({name: "label", value: el.label || ""}), " - shown in the form"]),
	],
	paragraph: el => [ //extcall
		render_element[""](el, "Paragraph input"),
		LABEL(["Label: ", INPUT({name: "label", value: el.label || ""}), " - shown in the form"]),
	],
	address: el => [ //extcall
		render_element[""](el, "Address"),
		P("The labels for the fields may be changed as required."),
		address_parts.map(([name, lbl]) =>
			[LABEL([SPAN(lbl + ":"), INPUT({name: "label-" + name, value: el["label-" + name] || lbl})]), BR()]
		),
		P(["Note that this makes a number of assumptions which may not always be correct.", BR(),
			"Depending on which country your mail is going to, it may be preferable to use a simple", BR(),
			"paragraph input and allow the address to be written free-form."]),
	],
	//({"radio", "Selection (radio) buttons"}),
	checkbox: el => [ //extcall
		render_element[""](el, "Set of checkboxes"),
		UL([
			(el.label || []).map((l, i) =>
				LI([
					LABEL(["Label " + (i+1) + ": ", INPUT({name: "label[" + i + "]", value: l || ""})]),
					" ",
					BUTTON({type: "button", class: "deletefield", "data-field": "label[" + i + "]"}, "x"),
				])
			),
			LI(LABEL(["Add label: ", INPUT({name: "label[" + (el.label || []).length + "]", value: "", "data-addnew": "1"})])),
		]),
	],
	text: el => [ //extcall
		//Not using render_element[""]() as we want to vary this a little (no "Required", larger description box)
		P("Informational text - supports Markdown"),
		LABEL(["Description:", BR(), TEXTAREA({name: "text", value: el.text || "", rows: 10, cols: 80})]),
	],
};

let editing = null;
function openform(f) {
	editing = f.id;
	["id", "formtitle", "is_open", "mods_see_responses", "thankyou"].forEach(key => {
		const el = DOM("#editformdlg [name=" + key + "]");
		if (el.type === "checkbox") el.checked = !!f[key];
		else el.value = f[key] || "";
	});
	DOM("#viewform").href = "form?form=" + f.id;
	DOM("#viewresp").href = "form?responses=" + f.id;
	replace_content("#formelements", (f.elements||[]).map((el, idx) => DIV({class: "element", "data-idx": idx}, [
		DIV({class: "header"}, [
			LABEL(["Field name: ", INPUT({name: "name", value: el.name || ""}), " - must be unique"]),
			BUTTON({class: "moveelement", type: "button", "data-dir": -1, disabled: idx === 0}, "Up"),
			BUTTON({class: "moveelement", type: "button", "data-dir":  1, disabled: idx === f.elements.length - 1}, "Dn"),
			BUTTON({class: "delelement", type: "button"}, "x"),
		]),
		(render_element[el.type] || render_element[""])(el),
	])));
	DOM("#editformdlg").showModal();
}
on("click", ".openform", e => {e.preventDefault(); openform(e.match.form_data);});

on("click", "#createform", e => ws_sync.send({cmd: "create_form"}));
export function sockmsg_openform(msg) {openform(msg.form_data);}
const groupable = { //_element_types that can be used for grouping
	//Note that twitchid doesn't actually work due to how it's stored
	simple: v => v.toLowerCase(),
	url: v => v,
	//When grouping by address, ignore the Name line and group identical delivery points.
	address: v => v.toLowerCase().split("\n").slice(1).join("\n"),
	//checkbox might be nice, but you'd have to choose which one (if there are multiple)
};
const grouptypes = { }; //Map element name to the groupable type
export function render(data) {
	if (data.forms) data.forms.forEach(f => f.id === editing && openform(f));
	if (data.forminfo) replace_content("#groupfield", [
		OPTION({value: ""}, "Select field..."),
		data.forminfo.elements && data.forminfo.elements.map(el => groupable[grouptypes[el.name] = el.type] && OPTION({value: el.name}, el.label || el.name)),
	]);
	if (data.responses) {
		let highlight = false, lastfield = "";
		const response_groupfield = DOM("#groupfield").value;
		replace_content("#responses tbody", data.responses.map(r => {
			let matches = [r];
			let grp = null, grpfold = v => v;
			if (response_groupfield && r.fields && !r.archived) {
				if (r.river) return;
				//Scan the rest of the responses to see if there are any others with the same groupfield
				//Not applicable to entries that lack fields (ie unsubmitted permissions), they will not be grouped.
				//TODO: Allow grouping by permitted/submitted user??
				grpfold = groupable[grouptypes[response_groupfield]];
				grp = grpfold(r.fields[response_groupfield]);
				matches = data.responses.filter(r => !r.river && r.fields && !r.archived && grpfold(r.fields[response_groupfield]) === grp);
				r.river = true;
				matches.forEach(r => r.river = true);
			}
			const seenuser = { };
			return TR({class: r.archived ? "archived" : (highlight = !highlight) ? "row-alternate" : "row-default"}, [
				TD(matches.map(r => [INPUT({type: "checkbox", "data-nonce": r.nonce, class: "selectrow"}), BR()])),
				TD(matches.map(r => [format_time(r.permitted), BR()])),
				TD(matches.map(r => [format_time(r.timestamp), BR()])),
				TD(matches.map(r => {
					const user = r.submitted_by || r.authorized_for;
					if (seenuser[user.id]) return null;
					seenuser[user.id] = 1;
					return [format_user(user), BR()];
				})),
				TD(matches.map(r => [BUTTON({type: "button", class: "showresponse", ".resp_data": r}, "View"), BR()])),
				//Note that we aren't using the folded version here (as it'll potentially have been uglified in the process)
				grp && TD({style: "white-space: pre-line"}, matches[0].fields[response_groupfield]),
			]);
		}));
	}
}

on("change", "#groupfield", e => ws_sync.send({cmd: "refresh"})); //me is lazy

on("change", ".formmeta", e => ws_sync.send({cmd: "form_meta", id: editing, [e.match.name]: e.match.type === "checkbox" ? e.match.checked : e.match.value}));

on("click", "#addelement", e => {
	if (e.match.value != "") ws_sync.send({cmd: "add_element", id: editing, "type": e.match.value});
	e.match.value = "";
});

on("click", ".delelement", e => ws_sync.send({cmd: "delete_element", id: editing, idx: +e.match.closest_data("idx")}));

on("click", ".moveelement", e => ws_sync.send({cmd: "move_element", id: editing, idx: +e.match.closest_data("idx"), dir: +e.match.dataset.dir}));

on("click", "#delete_form", simpleconfirm("Are you sure? This cannot be undone!", e => {
	ws_sync.send({cmd: "delete_form", id: editing});
	DOM("#editformdlg").close();
}));

on("change", ".element input,.element textarea", e => {
	ws_sync.send({
		cmd: "edit_element", id: editing, idx: +e.match.closest_data("idx"),
		field: e.match.name, value: e.match.type === "checkbox" ? e.match.checked : e.match.value,
	});
	if (e.match.dataset.addnew) e.match.value = "";
});

on("click", ".element .deletefield", e => ws_sync.send({cmd: "edit_element", id: editing, idx: +e.match.closest_data("idx"), field: e.match.dataset.field, value: ""}));

//Allow range selection of rows
let last_clicked = null;
on("click", ".selectrow", e => {
	let state = e.match.checked;
	if (e.shiftKey && last_clicked && last_clicked.checked === state) {
		const pos = e.match.compareDocumentPosition(last_clicked);
		let from, to;
		if (pos & 2) {to = e.match.closest("tr"); from = last_clicked.closest("tr");}
		else if (pos & 4) {from = e.match.closest("tr"); to = last_clicked.closest("tr");}
		//Else something went screwy. Ignore the shift and just select this one.
		for (;from && from !== to; from = from.nextSibling) {
			const cb = from.querySelector(".selectrow");
			if (cb) cb.checked = state;
		}
	}
	last_clicked = e.match;
	//So! Are any selected? If the current one is, no need to search; otherwise, see if there are any.
	if (!state && document.querySelector(".selectrow:checked")) state = true;
	DOM("#archiveresponses").disabled = DOM("#deleteresponses").disabled = !state;
	//If at least one is selected, and all selected rows are currently archived,
	//the Archive button becomes Unarchive.
	if (!state || document.querySelector("tr:not(.archived) .selectrow:checked"))
		replace_content("#archiveresponses", "Archive selected").dataset.cmd = "archive_responses";
	else
		replace_content("#archiveresponses", "Unarchive selected").dataset.cmd = "unarchive_responses";
});

on("click", "#archiveresponses", e => {
	const nonces = [];
	document.querySelectorAll(".selectrow:checked").forEach(el => {nonces.push(el.dataset.nonce); el.checked = false;});
	ws_sync.send({cmd: e.match.dataset.cmd || "archive_responses", nonces});
});

on("click", "#deleteresponses", simpleconfirm("Deleted responses are hard to retrieve. Are you sure you want to do this?", e => {
	const nonces = [];
	document.querySelectorAll(".selectrow:checked").forEach(el => {nonces.push(el.dataset.nonce); el.checked = false;});
	ws_sync.send({cmd: "delete_responses", nonces});
}));

on("click", "#downloadcsv", e => {
	const nonces = [];
	document.querySelectorAll(".selectrow:checked").forEach(el => nonces.push(el.dataset.nonce));
	if (nonces.length === 0) document.querySelectorAll(".selectrow").forEach(el => nonces.push(el.dataset.nonce));
	ws_sync.send({cmd: "download_csv", nonces});
});
export function sockmsg_download_csv(msg) {
	const link = choc.A({href: "data:text/csv;charset=UTF-8," + encodeURIComponent(msg.csvdata), download: "formresponses.csv"});
	document.body.appendChild(link);
	link.click();
	link.remove();
}

const view_element = { //Matches _element_types (see Pike code)
	twitchid: (el, r) => format_user(r.submitted_by || r.authorized_for),
	simple: (el, r) => [LABEL(SPAN(el.label)), PRE(r.fields[el.name])],
	url: (el, r) => [LABEL(SPAN(el.label)), A({href: r.fields[el.name]}, r.fields[el.name])],
	paragraph: (el, r) => [LABEL(SPAN(el.label)), BR(), PRE(r.fields[el.name])],
	address: (el, r) => DIV({class: "twocol"}, [
		PRE(r.fields[el.name]),
		DIV({class: "column"}, BUTTON({class: "clipbtn", "data-copyme": r.fields[el.name],
			title: "Click to copy address"}, "📋")),
	]),
	checkbox: (el, r) => UL([
		(el.label || []).map((l, i) => LI({class: r.fields[el.name + (-i || "")] ? "checkbox-checked" : "checkbox-unchecked"}, [
			LABEL(SPAN(r.fields[el.name + (-i || "")] ? "Selected" : "Unselected")),
			" ", l,
		])),
	]),
};

on("click", ".showresponse", e => {
	const r = e.match.resp_data;
	["permitted", "timestamp"].forEach(key => {
		const el = DOM("#responsedlg [name=" + key + "]");
		if (r[key]) {
			const t = new Date(r[key] * 1000);
			el.value = t.toLocaleString();
		}
		else el.value = "";
	});
	if (r.archived) {
		const t = new Date(r.archived * 1000);
		replace_content("#archived_at", "Archived at " + t.toLocaleString());
	}
	if (r.fields) replace_content("#formresponse tbody", (formdata.elements||[]).map((el, idx) => view_element[el.type] && TR([
		TD(el.name),
		TD(view_element[el.type](el, r)),
	])));
	else replace_content("#formdesc", [
		P(["Form has not been submitted (was permitted ", format_timedelta(new Date / 1000 - r.permitted), ")"]),
		P(A({href: "form?nonce=" + r.nonce, target: "_blank"}, "Form submission link")),
		P("Provide this to the permitted user."),
	]);
	DOM("#formresponse").hidden = !r.fields
	DOM("#formdesc").hidden = !!r.fields
	DOM("#responsedlg").showModal();
});
