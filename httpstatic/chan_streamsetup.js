import {choc, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, SPAN, TD, TR} = choc; //autoimport
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
	pick_setup(setup);
});
function pick_setup(setup) {
	const setupform = DOM("#setupconfig").elements;
	setupform.category.value = setup.category;
	setupform.title.value = setup.title;
	setupform.tags.value = setup.tags;
	setupform.ccls.value = setup.ccls;
	setupform.comments.value = setup.comments;
	DOM("#setupconfig").classList.add("dirty");
}

on("input", "#setupconfig input", e => e.match.form.classList.add("dirty"));

on("submit", "#setupconfig", e => {
	e.preventDefault();
	const el = DOM("#setupconfig").elements;
	const msg = {cmd: "applysetup"};
	"category title tags ccls".split(" ").forEach(id => msg[id] = el[id].value);
	ws_sync.send(msg);
	e.match.classList.remove("dirty");
});

let prevsetup = { };
export function sockmsg_prevsetup(msg) {
	prevsetup = msg.setup;
	set_content("#prevsetup", [
		SPAN("Previous setup:"),
		SPAN(prevsetup.category),
		SPAN(prevsetup.title),
		SPAN(prevsetup.tags),
		SPAN(BUTTON({onclick: () => pick_setup(prevsetup)}, "Reapply")),
		SPAN(BUTTON({id: "saveprev"}, "Save")),
	]).style.display = "block";
}

on("click", "#saveprev", e => {
	const msg = {cmd: "newsetup"};
	"category title tags ccls comments".split(" ").forEach(id => msg[id] = prevsetup[id]);
	ws_sync.send(msg);
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

if (initialsetup) {
	const el = DOM("#setupconfig").elements;
	el.category.value = initialsetup.game_name;
	el.ccls.value = initialsetup.content_classification_labels.join(", "); //TODO: Are they just strings?
	el.title.value = initialsetup.title;
	el.tags.value = initialsetup.tags.join(", ");
}
