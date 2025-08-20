import {choc, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, DIV, IMG, INPUT, LABEL, LI, OPTION, P, PRE, SPAN, TD, TEXTAREA, TIME, TR, UL} = choc; //autoimport
import {simpleconfirm, simplemessage} from "$$static||utils.js$$";

export const autorender = {
	unlock_parent: DOM("#unlocks"),
	unlock(f) {return LI({"data-id": f.id, class: "openform", ".form_data": f}, [
		f.id, " ", f.formtitle,
	]);},
	unlock_empty() {return DOM("#unlocks").appendChild(LI([
		"Work with the community to unlock these things!",
	]));},
	allunlock_parent: DOM("#allunlocks"),
	allunlock(f) {return LI({"data-id": f.id, class: "openform", ".form_data": f}, [
		f.id, " ", f.formtitle,
	]);},
	allunlock_empty() {return DOM("#allunlocks").appendChild(LI([
		"No unlocks yet - add one to get started.",
	]));},
}

let pending_var_selection;
export function render(data) {
	if (DOM("#varname").firstChild) DOM("#varname").value = data.varname;
	else pending_var_selection = data.varname;
}

on("click", "#addunlock", e => ws_sync.send({cmd: "add_unlock"}));
on("change", "#varname", e => ws_sync.send({cmd: "config", varname: e.match.value}));

const variables = { };
if (ws_group.startsWith("control#")) {
	document.querySelectorAll(".modonly").forEach(el => (el.hidden = false));
	ws_sync.connect(ws_group, {
		ws_type: "chan_variables", ws_sendid: "chan_variables",
		render_parent: DOM("#varname"),
		render_item: (v, obj) => {variables[v.id] = v.curval; return obj || OPTION({"data-id": v.id}, v.id)},
		render: function(data) {
			if (pending_var_selection) DOM("#varname").value = pending_var_selection;
			pending_var_selection = null;
		},
	});
}
