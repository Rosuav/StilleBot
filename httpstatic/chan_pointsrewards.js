import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, IMG, INPUT, LABEL, LI, OPTION, TBODY, TD, TEXTAREA, TR, UL} = choc; //autoimport
import {commands, cmd_configure, open_advanced_view} from "$$static||command_editor.js$$";
import {simpleconfirm} from "$$static||utils.js$$";

export const render_parent = DOM("#rewards tbody");
export function render_item(rew) {
	return TR({"data-id": rew.id, ".reward_details": rew}, [
		TD({style: "background: " + rew.background_color}, IMG({src:
			rew.image ? rew.image.url_1x //If an image is selected
			: rew.default_image.url_1x //Otherwise, the default fallback
		})),
		TD(rew.title),
		TD(rew.prompt),
		TD({title: rew.can_manage
			? "Reward can be managed by Mustard Mine" + (rew.should_redemptions_skip_request_queue ? " (redemptions skip queue)" : "")
			: "Reward created elsewhere, can attach functionality only"},
			rew.can_manage ? BUTTON({type: "button", class: "editreward"}, "\u2699") : "❎"
		),
		TD(UL([
			//NOTE: The invocations are simple names eg "coinflip", but the command editor
			//expects them to match the commands array, which shows eg "coinflip#rosuav".
			//We assume that ws_group is always just the channel, no actual group.
			rew.invocations.map(c => LI({"data-id": c}, BUTTON({class: "advview"}, "!" + c))),
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
	if (data.items) set_content(sel, [
		sel.firstElementChild,
		data.items.map(rew => OPTION({value: rew.id}, rew.title)),
	]).value = val;
}

on("click", ".addcmd", e => {
	let i = 1;
	while (commands["untitled" + i + ws_group]) ++i;
	open_advanced_view({
		id: "untitled" + i, template: true, access: "none", visibility: "hidden",
		message: [
			"@{username}, you redeemed: " + e.match.dataset.title,
			//TODO: Include this only if the reward doesn't skip the queue
			{builtin: "chan_pointsrewards", builtin_param: ["{rewardid}", "fulfil", "{redemptionid}"], message: ""},
		],
		redemption: e.match.dataset.reward,
	})
});

on("click", "#add", e => ws_sync.send({cmd: "add", copyfrom: DOM("#copyfrom").value}));

const limit = attrs => [INPUT({...attrs, type: "number"}), " (blank for unlimited)"];
const reward_editing_elements = {
	"": attrs => INPUT(attrs),
	prompt: attrs => TEXTAREA({...attrs, rows: 3, cols: 40}),
	cost: attrs => INPUT({...attrs, type: "number"}),
	background_color: attrs => INPUT({...attrs, type: "color"}),
	flags: attrs => [
		//Group some checkboxes into a single row
		LABEL([INPUT({name: "is_enabled", type: "checkbox"}), " Enabled"]), BR(),
		LABEL([INPUT({name: "is_paused", type: "checkbox"}), " Paused"]), BR(),
		LABEL([INPUT({name: "is_user_input_required", type: "checkbox"}), " Prompt for text"]), BR(),
		LABEL([INPUT({name: "should_redemptions_skip_request_queue", type: "checkbox"}), " Auto-fulfil"]), BR(),
	],
	max_per_stream: limit, max_per_user_per_stream: limit, global_cooldown_seconds: limit,
};
const reward_attributes = {
	title: "Title",
	prompt: "Description",
	cost: "Cost",
	background_color: "Color",
	flags: "",
	max_per_stream: "Max per stream",
	max_per_user_per_stream: "Max per user",
	global_cooldown_seconds: "Cooldown (seconds)",
};
set_content("#rewardfields", TBODY(Object.entries(reward_attributes).map(([field, label]) => {
	const attrs = {id: "rew_" + field, name: field};
	const fac = reward_editing_elements[field] || reward_editing_elements[""];
	return TR([
		TD(label && LABEL({for: attrs.id}, label)),
		TD(fac(attrs)),
	]);
})));

let editing_reward = null;
on("click", ".editreward", e => {
	const rew = e.match.closest("tr").reward_details;
	editing_reward = e.match.closest_data("id");
	const form = DOM("#editrewarddlg form").elements;
	//Special-case the paired fields by removing the info if it's not enabled
	//I'm not sure in what situations you'd want (say) a cooldown to be saved, but not enabled,
	//but for our purposes it may as well just not be there.
	for (let field of ["max_per_stream", "max_per_user_per_stream", "global_cooldown_seconds"]) {
		//If only the flag had been called "global_cooldown_seconds_setting".....
		const flag = field.replace("_seconds", "") + "_setting";
		rew[field] = rew[flag]?.is_enabled ? rew[flag][field] : "";
	}
	for (let field in rew) {
		const elem = form[field];
		if (elem) elem[elem.type === "checkbox" ? "checked" : "value"] = rew[field];
	}
	DOM("#editrewarddlg").showModal();
});

on("submit", "#editrewarddlg form", e => {
	const msg = {cmd: "update_reward", reward_id: editing_reward};
	const form = DOM("#editrewarddlg form").elements;
	for (let elem of form) if (elem.name) {
		const val = elem[elem.type === "checkbox" ? "checked" : "value"];
		if (elem.type === "number") msg[elem.name] = +val;
		else msg[elem.name] = val;
	}
	//Special-case the paired fields again, but note that the update fields aren't the same as the query fields.
	for (let field of ["max_per_stream", "max_per_user_per_stream", "global_cooldown_seconds"]) {
		const flag = "is_" + field.replace("_seconds", "") + "_enabled";
		const val = +msg[field];
		msg[flag] = !!val;
		msg[field] = val; //Note that this will set it to zero in addition to setting the enabled field to false. I don't get it, but this is what the API wants.
	}
	ws_sync.send(msg);
});

on("click", "#deletereward", simpleconfirm("Are you sure you want to delete this reward? Cannot be undone!", e => {
	ws_sync.send({cmd: "delete_reward", reward_id: editing_reward});
	DOM("#editrewarddlg").close();
}));

cmd_configure({
	get_command_basis: cmd => {
		const cmdname = "!" + cmd.id.split("#")[0];
		set_content("#advanced_view h3", ["Command name ", INPUT({autocomplete: "off", id: "cmdname", value: cmdname})]);
		return {type: "anchor_command"};
	},
});
ws_sync.send({cmd: "subscribe", type: "cmdedit", group: ""});
