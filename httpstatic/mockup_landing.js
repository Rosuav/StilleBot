import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, LI} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

export function render(data) {
	replace_content("#allmockups", [
		data.allmocks.map(m => LI(A({href: "mockup?view=" + m.id + "&edit=", target: "_blank"}, m.title))), //TODO: Show creation date?
		!data.allmocks.length && LI("(none)"),
	]);
}

on("click", "#create_mockup", e => ws_sync.send({cmd: "create_mockup"}));
export function sockmsg_mockup_created(msg) {
	window.open("/mockup?view=" + msg.id + "&edit=", "_blank");
}
