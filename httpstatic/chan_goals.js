import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {LI, SPAN, UL} = choc; //autoimport

//Describe the goal, in a way grammatically suited to "5 / 10 followers"
const goaltypes = {
	follower: "followers",
	subscription: "sub points",
	subscription_count: "subs",
	new_subscription: "new sub points",
	new_subscription_count: "new subs",
	new_bit: "bits",
	new_cheerer: "cheerers",
};

export const render_parent = DOM("#goals");
export function render_item(goal) {
	return LI({"data-id": goal.id}, [
		goal.description || "Goal", " ",
		goal.current_amount + "", " / ", goal.target_amount + "",
		" ", goaltypes[goal.type] || "of something",
		" (id ", goal.id, ")",
	]);
}


export function render(data) {
}
