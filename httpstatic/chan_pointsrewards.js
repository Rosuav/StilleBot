import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, IMG, LI, TD, TR, UL} = choc; //autoimport

export const render_parent = DOM("#rewards tbody");
export function render_item(rew) {
	return TR([
		TD({style: "background: " + rew.background_color}, IMG({src:
			rew.image ? rew.image.url_1x //If an image is selected
			: rew.default_image.url_1x //Otherwise, the default fallback
		})),
		TD(rew.title),
		TD(rew.prompt),
		TD({title: rew.can_manage
			? "Reward can be managed by StilleBot" + (rew.should_redemptions_skip_request_queue ? " (redemptions skip queue)" : "")
			: "Reward created elsewhere, can attach functionality only"},
			rew.can_manage ? "✅" + (rew.should_redemptions_skip_request_queue ? "⤐" : "") : "❎"
		),
		TD(UL(rew.invocations.map(c => LI(A({href: "commands#" + c.split("#")[0] + "/", target: "_blank"}, "!" + c.split("#")[0]))))),
	]);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 5}, "No redemptions (add one!)"),
	]));
}
export function render(data) { }
