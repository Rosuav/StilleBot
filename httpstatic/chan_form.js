import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, DIV, INPUT, LABEL, LI, P} = choc; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

export const autorender = {
	form_parent: DOM("#forms"),
	form(f) {return LI({"data-id": f.id, class: "openform", ".form_data": f}, [ //extcall
		f.id, " ", f.formtitle,
	]);},
	form_empty() {return DOM("#forms").appendChild(LI([
		"No forms yet - create one!",
	]));},
}

export function render(data) { }

const render_element = {
	"": el => "Unknown element type - something went wrong - " + el.type,
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
	//({"paragraph", "Paragraph input"}),
	//({"address", "Street address"}),
	//({"radio", "Selection (radio) buttons"}),
	//({"checkbox", "Check box(es)"}),
};

let editing = null;
function openform(f) {
	editing = f.id;
	["id", "formtitle"].forEach(key => {
		DOM("#editformdlg [name=" + key + "]").value = f[key] || "";
	});
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

on("change", ".formmeta", e => ws_sync.send({cmd: "form_meta", id: editing, [e.match.name]: e.match.value}));

on("click", "#addelement", e => {
	if (e.match.value != "") ws_sync.send({cmd: "add_element", id: editing, "type": e.match.value});
	e.match.value = "";
});

on("click", ".delelement", e => ws_sync.send({cmd: "delete_element", id: editing, idx: +e.match.closest_data("idx")}));

on("click", "#delete_form", simpleconfirm("Are you sure? This cannot be undone!", e => {
	ws_sync.send({cmd: "delete_form", id: editing});
	DOM("#editformdlg").close();
}));
