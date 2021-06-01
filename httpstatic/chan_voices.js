import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {CODE, BR, TR, TD, SPAN, DIV, UL, LI, INPUT} = choc;

export const render_parent = DOM("#voices tbody");
export function render_item() {
	return TR();
}
export function render_empty() {
	render_parent.appendChild(TR([
		TD({colSpan: 3}, "No additional voices."),
	]));
}
export function render(data) { }

on("click", "#addvoice", e => {
	ws_sync.send({cmd: "login"});
});

export function sockmsg_login(data) {
	console.log("Login!", data);
}
