import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, CODE, INPUT, LABEL, LI, OPTION, SELECT, SPAN, UL} = choc; //autoimport

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

let editing = null;
function openform(f) {
	editing = f.id;
	["id", "formtitle"].forEach(key => {
		DOM("#editformdlg [name=" + key + "]").value = f[key] || "";
	});
	DOM("#editformdlg").showModal();
}
on("click", ".openform", e => {e.preventDefault(); openform(e.match.form_data);});

on("click", "#createform", e => ws_sync.send({cmd: "create_form"}));
export function sockmsg_openform(msg) {openform(msg.form_data);}

on("change", ".formmeta", e => ws_sync.send({cmd: "form_meta", id: editing, [e.match.name]: e.match.value}));
