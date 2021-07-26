import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {TR, TD} = choc;

export const render_parent = DOM("#features tbody");
export function render_item(msg) {
	return TR({"data-id": msg.id}, [
		TD(msg.id),
		TD(msg.desc),
		TD("Check box goes here"),
	]);
}

export function render(data) {
	if (data.defaultstate) set_content("#defaultstate", data.defaultstate);
}
