import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {DIV, TR, TD, IMG, INPUT, TEXTAREA, BUTTON} = choc;
import {waitlate} from "$$static||utils.js$$";

export const render_parent = DOM("#voices tbody");
export function render_item(item) {
	//item.last_auth_time and (possibly) item.last_error_time - if auth < error,
	//suggest reauthenticating
	return TR({"data-id": item.id}, [
		TD([IMG({src: item.profile_image_url, className: "avatar"}), item.name]),
		TD(INPUT({value: item.desc, className: "desc", size: 15})),
		TD(TEXTAREA({value: item.notes || "", className: "notes", rows: 3, cols: 50})),
		TD(DIV([
			BUTTON({type: "button", className: "save"}, "Save"),
			BUTTON({type: "button", className: "delete"}, "Delete"),
		])),
	]);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 4}, "No additional voices."),
	]));
}
export function render(data) { }

on("click", "#addvoice", e => ws_sync.send({cmd: "login"}));
export function sockmsg_login(data) {window.open(data.uri, "login", "width=525, height=900");}

on("click", ".save", e => {
	const tr = e.match.closest("tr");
	const msg = {cmd: "update", id: tr.dataset.id};
	msg.desc = tr.querySelector(".desc").value;
	msg.notes = tr.querySelector(".notes").value;
	ws_sync.send(msg);
});

on("click", ".delete", waitlate(750, 5000, "Really delete?", e => {
	ws_sync.send({cmd: "delete", id: e.match.closest("tr").dataset.id});
}));
