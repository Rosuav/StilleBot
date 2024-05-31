import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {LI, SPAN, UL} = choc; //autoimport

export const render_parent = DOM("#goals");
export function render_item(goal) {
	let type = "of something";
	if (goal.type === "subscription") type = "subs";
	//Bits goal came through with a blank type! Argh!
	return LI({"data-id": goal.id}, [
		goal.description || "Goal", " ",
		goal.current_amount + "", " / ", goal.target_amount + "",
		" ", type, " (id ", goal.id, ")"
	]);
}


export function render(data) {
}
