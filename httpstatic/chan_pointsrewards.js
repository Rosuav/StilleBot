import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, IMG, INPUT, LI, TD, TR, UL} = choc; //autoimport
import {sockmsg_validated, commands, render_command, cmd_configure, open_advanced_view} from "$$static||command_editor.js$$";

export const render_parent = DOM("#rewards tbody");
export function render_item(rew) {
	return TR({"data-id": rew.id}, [
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
		TD(UL([
			rew.invocations.map(c => LI({"data-id": c}, BUTTON({class: "advview"}, "!" + c.split("#")[0]))),
			LI(BUTTON({class: "addcmd", "data-title": rew.title, "data-reward": rew.id}, "New")),
		])),
	]);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 5}, "No redemptions (add one!)"),
	]));
}
export function render(data) { }

on("click", ".addcmd", e => {
	let i = 1;
	while (commands["untitled" + i + ws_group]) ++i;
	open_advanced_view({
		id: "untitled" + i, template: true, access: "none", visibility: "hidden",
		message: "@{username}, you redeemed: " + e.match.dataset.title,
		redemption: e.match.dataset.reward,
	})
});

cmd_configure({
	get_command_basis: cmd => {
		const cmdname = "!" + cmd.id.split("#")[0];
		set_content("#advanced_view h3", ["Command name ", INPUT({autocomplete: "off", id: "cmdname", value: cmdname})]);
		let automate = "";
		if (cmd.automate) {
			const [m1, m2, mode] = cmd.automate;
			if (mode) automate = ("0" + m1).slice(-2) + ":" + ("0" + m2).slice(-2); //hr:min
			else if (m1 === m2) automate = ""+m1; //min-min is the same as just min
			else automate = m1 + "-" + m2; //min-max
		}
		return {type: "anchor_command", aliases: cmd.aliases || "", automate};
	},
});

ws_sync.connect(ws_group, {
	ws_type: "chan_commands", ws_sendid: "cmdedit",
	render_parent: UL(), //Don't actually need them rendered anywhere
	render_item: render_command, sockmsg_validated, render: data => { },
});
