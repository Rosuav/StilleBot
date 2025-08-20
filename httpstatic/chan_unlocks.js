import {choc, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, HR, IMG, INPUT, LABEL, LI, OPTION, SPAN} = choc; //autoimport
import {simpleconfirm, simplemessage} from "$$static||utils.js$$";
import {formatters} from "$$static||monitor.js$$";

let format = formatters.plain;
export const autorender = {
	unlock_parent: DOM("#unlocks"),
	unlock(f) {return LI({"data-id": f.id}, [ //extcall
		"Unlocked at ", SPAN({class: "thresholddisplay", "data-threshold": f.threshold}, format(f.threshold)), "!", BR(),
		IMG({src: f.url, class: "preview"}),
		HR(),
	]);},
	unlock_empty() {return DOM("#unlocks").appendChild(LI([
		"Work with the community to unlock these things!",
	]));},
	allunlock_parent: DOM("#allunlocks"),
	allunlock(f) {return LI({"data-id": f.id}, [ //extcall
		LABEL(["Unlock at ", INPUT({class: "threshold", type: "number", value: f.threshold || 1})]),
		BUTTON({type: "button", class: "confirmdelete", title: "Delete"}, "🗑"), BR(),
		"NOTE: Set the threshold before uploading the image, or it will be unexpectedly visible!", BR(),
		LABEL(["Image URL: ", INPUT({class: "url", value: f.url || ""})]), BR(),
		"TODO: Allow direct uploads. For now, they need to be provided as links to somewhere.",
	]);},
	allunlock_empty() {return DOM("#allunlocks").appendChild(LI([
		"No unlocks yet - add one to get started.",
	]));},
	varname_parent: DOM("[name=varname]"),
	varname: (v, obj) => obj || OPTION({"data-id": v.id}, v.id), //extcall
}

let pending_var_selection;
export function render(data) {
	document.querySelectorAll(".config").forEach(el => {
		if (data[el.name]) el.value = data[el.name];
	});
	if (data.format) {
		format = formatters[data.format] || formatters.plain;
		document.querySelectorAll(".thresholddisplay").forEach(el => set_content(el, format(el.dataset.threshold)));
	}
	set_content("#nextunlock", data.nextval ? ["NEXT UNLOCK AT ", format(data.nextval), "!"] : "");
}

on("click", "#addunlock", e => ws_sync.send({cmd: "add_unlock"}));
on("change", ".config", e => ws_sync.send({cmd: "config", [e.match.name]: e.match.value}));
on("click", ".confirmdelete", simpleconfirm("Really delete this unlock?", e =>
	ws_sync.send({cmd: "delete_unlock", id: e.match.closest_data("id")})
));
on("change", ".threshold", e => ws_sync.send({cmd: "update_unlock", id: e.match.closest_data("id"), threshold: e.match.value}));
on("change", ".url", e => ws_sync.send({cmd: "update_unlock", id: e.match.closest_data("id"), url: e.match.value}));

on("click", ".preview", e => e.match.requestFullscreen());

if (ws_group.startsWith("control#")) document.querySelectorAll(".modonly").forEach(el => (el.hidden = false));
