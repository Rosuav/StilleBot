import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, DIV, INPUT, LABEL, LI, P, PRE, TD, TEXTAREA, TIME, TR, UL} = choc; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

function format_time(ts) {
	if (!ts) return "";
	const t = new Date(ts * 1000);
	//TODO: Make an abbreviated form for the initial display
	//For anything today, just show the time. For something this week, "Thu 12:30".
	//For something older than that, just show the date.
	return TIME({datetime: t.toISOString(), title: t.toLocaleString()}, t.toLocaleString());
}

export const autorender = {
	form_parent: DOM("#forms"),
	form(f) {return LI({"data-id": f.id, class: "openform", ".form_data": f}, [ //extcall
		f.id, " ", f.formtitle,
	]);},
	form_empty() {return DOM("#forms").appendChild(LI([
		"No forms yet - create one!",
	]));},
}

const render_element = { //Matches _element_types (see Pike code)
	"": el => P("Unknown element type - something went wrong - " + el.type),
	//({"twitchid", "Twitch username"}), //If mandatory, will force user to be logged in to submit
	simple: el => [ //extcall
		P("Text input"),
		LABEL(["Label: ", INPUT({name: "label", value: el.label || ""}), " - shown in the form"]),
		//Type (numeric/text)?
	],
	paragraph: el => [ //extcall
		P("Paragraph input"),
		LABEL(["Label: ", INPUT({name: "label", value: el.label || ""}), " - shown in the form"]),
	],
	//({"address", "Street address"}),
	//({"radio", "Selection (radio) buttons"}),
	checkbox: el => [ //extcall
		P("Set of checkboxes"),
		UL([
			(el.label || []).map((l, i) =>
				LI([
					LABEL(["Label " + (i+1) + ": ", INPUT({name: "label[" + i + "]", value: l || ""})]),
					" ",
					BUTTON({type: "button", class: "deletefield", "data-field": "label[" + i + "]"}, "x"),
				])
			),
			LI(LABEL(["Add label: ", INPUT({name: "label[" + (el.label || []).length + "]", value: ""})])),
		]),
	],
	text: el => [ //extcall
		P("Informational text - supports Markdown"),
		TEXTAREA({name: "text", value: el.text || "", rows: 10, cols: 80}),
	],
};

let editing = null;
function openform(f) {
	editing = f.id;
	["id", "formtitle", "is_open"].forEach(key => {
		const el = DOM("#editformdlg [name=" + key + "]");
		if (el.type === "checkbox") el.checked = !!f[key];
		else el.value = f[key] || "";
	});
	DOM("#viewform").href = "form?form=" + f.id;
	DOM("#viewresp").href = "form?responses=" + f.id;
	set_content("#formelements", (f.elements||[]).map((el, idx) => DIV({class: "element", "data-idx": idx}, [
		DIV({class: "header"}, [
			LABEL(["Field name: ", INPUT({name: "name", value: el.name || ""}), " - must be unique"]),
			BUTTON({class: "moveup", type: "button", disabled: true}, "Up"),
			BUTTON({class: "movedn", type: "button", disabled: true}, "Dn"),
			BUTTON({class: "delelement", type: "button"}, "x"),
		]),
		(render_element[el.type] || render_element[""])(el),
	])));
	DOM("#editformdlg").showModal();
}
on("click", ".openform", e => {e.preventDefault(); openform(e.match.form_data);});

on("click", "#createform", e => ws_sync.send({cmd: "create_form"}));
export function sockmsg_openform(msg) {openform(msg.form_data);}
export function render(data) {
	if (data.forms) data.forms.forEach(f => f.id === editing && openform(f));
	if (data.responses) set_content("#responses tbody", data.responses.map(r => TR([
		TD(format_time(r.permitted)),
		TD(format_time(r.timestamp)),
		TD(),
		TD(BUTTON({type: "button", class: "showresponse", ".resp_data": r}, "View")),
	])));
}

on("change", ".formmeta", e => ws_sync.send({cmd: "form_meta", id: editing, [e.match.name]: e.match.type === "checkbox" ? e.match.checked : e.match.value}));

on("click", "#addelement", e => {
	if (e.match.value != "") ws_sync.send({cmd: "add_element", id: editing, "type": e.match.value});
	e.match.value = "";
});

on("click", ".delelement", e => ws_sync.send({cmd: "delete_element", id: editing, idx: +e.match.closest_data("idx")}));

on("click", "#delete_form", simpleconfirm("Are you sure? This cannot be undone!", e => {
	ws_sync.send({cmd: "delete_form", id: editing});
	DOM("#editformdlg").close();
}));

on("change", ".element input,.element textarea", e => ws_sync.send({cmd: "edit_element", id: editing, idx: +e.match.closest_data("idx"), field: e.match.name, value: e.match.value}));

on("click", ".element .deletefield", e => ws_sync.send({cmd: "edit_element", id: editing, idx: +e.match.closest_data("idx"), field: e.match.dataset.field, value: ""}));

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
	set_content("#formresponse", (formdata.elements||[]).map((el, idx) => DIV({class: "element"}, [
		DIV({class: "header"}, [
			"Field name: ", el.name
		]),
		PRE(r.fields[el.name]),
	])));
	DOM("#responsedlg").showModal();
});
