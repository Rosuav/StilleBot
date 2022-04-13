import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {LI, PRE} = choc;

export const render_parent = DOM("#rewards");
export function render_item(msg) {
	return LI({"data-id": msg.id}, PRE(JSON.stringify(msg, null, 4)));
}

export function render(data) { }
