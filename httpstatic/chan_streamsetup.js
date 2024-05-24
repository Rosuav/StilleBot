import {choc, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, TD, TR} = choc; //autoimport

export const render_parent = DOM("#setups tbody");
export function render_item(msg, obj) {
	return msg && TR([
		TD(msg.category), //Include box art?
		TD(msg.title),
		TD(msg.tags), //may need to be joined
		TD(msg.ccls), //ditto
		TD(msg.comments),
		TD(BUTTON("X")), //TODO
	]);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 6}, "No setups defined. Create one!"),
	]));
}
export function render(data) { }

on("submit", "#setupconfig", e => {
	e.preventDefault();
	//TODO: Update stream setup
});

on("click", "#save", e => {
	const el = DOM("#setupconfig").elements;
	console.log(el);
	const msg = {cmd: "newsetup"};
	"category title tags ccls comments".split(" ").forEach(id => msg[id] = el[id].value);
	ws_sync.send(msg);
});
