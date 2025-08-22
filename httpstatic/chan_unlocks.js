import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DIV, FIGCAPTION, FIGURE, HR, IMG, INPUT, LABEL, LI, OPTION, SPAN} = lindt; //autoimport
import {simpleconfirm, simplemessage, upload_to_library} from "$$static||utils.js$$";
import {formatters} from "$$static||monitor.js$$";

let format = formatters.plain;
export function render(data) {
	if (data.varnames) replace_content("[name=varname]", data.varnames.map(v => OPTION(v.id)));
	document.querySelectorAll(".config").forEach(el => {
		if (data[el.name]) el.value = data[el.name];
	});
	if (data.format) format = formatters[data.format] || formatters.plain;
	replace_content("#nextunlock", data.nextval ? ["NEXT UNLOCK AT ", format(data.nextval), "!"] : "");
	if (data.unlocks) replace_content("#unlocks", data.unlocks.length ? data.unlocks.map(f => LI({"key": f.id}, [
		"Unlocked at ", SPAN({class: "thresholddisplay"}, format(f.threshold)), "!", BR(),
		FIGURE([
			FIGCAPTION(f.caption),
			IMG({src: "/upload/" + f.fileid, class: "preview"}),
		]),
		HR(),
	])) : LI("Work with the community to unlock these things!"));
	if (data.allunlocks) replace_content("#allunlocks", data.allunlocks.map(f => LI({"key": f.id}, [
		DIV({class: "twocol"}, [
			DIV([
				LABEL(["Unlock at ", INPUT({"data-unlockfield": "threshold", type: "number", value: f.threshold || 1})]),
				BUTTON({type: "button", class: "confirmdelete", title: "Delete"}, "🗑"), BR(),
				LABEL(["Caption: ", INPUT({"data-unlockfield": "caption", value: f.caption || ""})]), BR(),
			]),
			DIV([
				IMG({src: "/upload/" + f.fileid, class: "preview small"}), BR(),
			]),
		]),
	])));
}

on("click", "#addunlock", e => ws_sync.send({cmd: "add_unlock"}));
on("change", ".config", e => ws_sync.send({cmd: "config", [e.match.name]: e.match.value}));
on("click", ".confirmdelete", simpleconfirm("Really delete this unlock?", e =>
	ws_sync.send({cmd: "delete_unlock", id: e.match.closest_data("id")})
));
on("change", "[data-unlockfield]", e => ws_sync.send({cmd: "update_unlock", id: e.match.closest_data("id"), [e.match.dataset.unlockfield]: e.match.value}));

on("click", ".preview", e => e.match.requestFullscreen());

upload_to_library({});

if (ws_group.startsWith("control#")) document.querySelectorAll(".modonly").forEach(el => (el.hidden = false));
