import {choc, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, TD, TR} = choc; //autoimport
import {simpleconfirm} from "./utils.js";

const setups = {}; //Keyed by ID

export const render_parent = DOM("#setups tbody");
export function render_item(msg, obj) {
	if (!msg) return 0;
	setups[msg.id] = msg;
	return TR({"data-id": msg.id}, [
		TD(msg.category), //Include box art?
		TD(msg.title),
		TD(msg.tags), //may need to be joined
		TD(msg.ccls), //ditto
		TD(msg.comments),
		TD(BUTTON({class: "delete"}, "X")), //TODO
	]);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 6}, "No setups defined. Create one!"),
	]));
}
export function render(data) { }

on("click", "#setups tr[data-id]", e => {
	console.log("click");
	const setup = setups[e.match.dataset.id];
	if (!setup) return; //Shouldn't happen
	const setupform = DOM("#setupconfig").elements;
	setupform.category.value = setup.category;
	setupform.title.value = setup.title;
	setupform.tags.value = setup.tags;
	setupform.ccls.value = setup.ccls;
	setupform.comments.value = setup.comments;
	DOM("#setupconfig").classList.add("dirty");
});

on("input", "#setupconfig input", e => e.match.form.classList.add("dirty"));

on("submit", "#setupconfig", e => {
	e.preventDefault();
	//TODO: Update stream setup (and remove Dirty flag - only here, not when you save)
});

on("click", "#save", e => {
	const el = DOM("#setupconfig").elements;
	const msg = {cmd: "newsetup"};
	"category title tags ccls comments".split(" ").forEach(id => msg[id] = el[id].value);
	ws_sync.send(msg);
});

on("click", ".delete", simpleconfirm("Delete this setup?", e => {
	ws_sync.send({cmd: "delsetup", id: e.match.closest("[data-id]").dataset.id});
}));
