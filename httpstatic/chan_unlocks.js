import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, DIV, FIGCAPTION, FIGURE, HR, IMG, INPUT, LABEL, LI, OPTION, SPAN} = lindt; //autoimport
import {simpleconfirm, simplemessage, upload_to_library} from "$$static||utils.js$$";
import {formatters} from "$$static||monitor.js$$";

let format = formatters.plain;
function slugify(x) {return x.replace(/[^A-Za-z0-9]/g, "").toLowerCase();}
let unlockcost = 0;
function displaycost(i) {return format((i+1) * unlockcost);} //The cost to unlock pics[i], formatted for a human
export function render(data) {
	if (data.varnames) replace_content("[name=varname]", data.varnames.map(v => OPTION(v.id)));
	document.querySelectorAll(".config").forEach(el => {
		if (data[el.name]) el.value = data[el.name];
	});
	if (data.format) format = formatters[data.format] || formatters.plain;
	if (data.unlockcost) set_content("#unlockcostdisplay", format(unlockcost = data.unlockcost));
	replace_content("#nextunlock", data.nextval ? [
		"NEXT UNLOCK AT ", format(data.nextval), " - just ", format(data.nextval - data.curval), " to go!",
	] : "");
	if (data.unlocks) replace_content("#unlocks", data.unlocks.length ? data.unlocks.map((f, i) => {
		const cost = displaycost(i), slug = slugify(cost);
		return LI({
			"key": f.id, "id": "unlock-" + slug,
		}, [
			"Unlocked at ", cost, "! ",
			A({href: "#unlock-" + slug, style: "text-decoration: none"}, "🔗"), BR(),
			FIGURE([
				FIGCAPTION(f.caption),
				IMG({src: "/upload/" + f.fileid, class: "preview"}),
			]),
			HR(),
		]);
	}).reverse() : LI("Work with the community to unlock these things!"));
	const unlocked = data.unlockcost && Math.floor(data.curval / data.unlockcost);
	if (data.allunlocks) replace_content("#allunlocks", data.allunlocks.map((f, i) => LI({
		"key": f.id, "data-id": f.id,
		class: i >= unlocked ? "locked" : "unlocked",
	}, [
		DIV({class: "twocol"}, [
			DIV([
				DIV([
					i >= unlocked ? "Unlock at " : "Unlocked at ",
					displaycost(i),
					" ",
					BUTTON({type: "button", class: "confirmdelete", title: "Delete"}, "🗑"), BR(),
				]),
				LABEL(["Caption: ", INPUT({"data-unlockfield": "caption", value: f.caption || ""})]), BR(),
			]),
			DIV([
				IMG({src: "/upload/" + f.fileid, class: "preview small"}), BR(),
			]),
		]),
	])).reverse());
}

on("click", "#shuffle", e => ws_sync.send({cmd: "shuffle"}));
on("change", ".config", e => ws_sync.send({cmd: "config", [e.match.name]: e.match.value}));
on("click", ".confirmdelete", simpleconfirm("Really delete this unlock?", e =>
	ws_sync.send({cmd: "delete_unlock", id: e.match.closest_data("id")})
));
on("change", "[data-unlockfield]", e => ws_sync.send({cmd: "update_unlock", id: e.match.closest_data("id"), [e.match.dataset.unlockfield]: e.match.value}));

on("click", ".preview", e => e.match.requestFullscreen());

upload_to_library({});

if (ws_group.startsWith("control#")) document.querySelectorAll(".modonly").forEach(el => (el.hidden = false));
