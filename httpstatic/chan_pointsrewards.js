import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, IMG, INPUT, LI, OPTION, TD, TR, UL} = choc; //autoimport
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
			rew.can_manage && LI(BUTTON({class: "addcmd", "data-title": rew.title, "data-reward": rew.id}, "New")),
		])),
	]);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 5}, "No redemptions (add one!)"),
	]));
}
export function render(data) {
	const sel = DOM("#copyfrom"), val = sel.value;
	set_content(sel, [sel.firstElementChild, data.items.map(rew => OPTION({value: rew.id}, rew.title))]).value = val;
}

on("click", ".addcmd", e => {
	let i = 1;
	while (commands["untitled" + i + ws_group]) ++i;
	open_advanced_view({
		id: "untitled" + i, template: true, access: "none", visibility: "hidden",
		message: [
			"@{username}, you redeemed: " + e.match.dataset.title,
			//TODO: Include this only if the reward doesn't skip the queue
			{builtin: "chan_pointsrewards", builtin_param: ["{rewardid}", "fulfil", "{redemptionid}"], message: {
				conditional: "string", expr1: "{error}",
				message: "", otherwise: "Unexpected error: {error}",
			}},
		],
		redemption: e.match.dataset.reward,
	})
});

on("click", "#add", e => ws_sync.send({cmd: "add", copyfrom: DOM("#copyfrom").value}));

cmd_configure({
	get_command_basis: cmd => {
		const cmdname = "!" + cmd.id.split("#")[0];
		set_content("#advanced_view h3", ["Command name ", INPUT({autocomplete: "off", id: "cmdname", value: cmdname})]);
		return {type: "anchor_command"};
	},
});

ws_sync.connect(ws_group, {
	ws_type: "chan_commands", ws_sendid: "cmdedit",
	render_parent: UL(), //Don't actually need them rendered anywhere
	render_item: render_command, sockmsg_validated, render: data => { },
});
