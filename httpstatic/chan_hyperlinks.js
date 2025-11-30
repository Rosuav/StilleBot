import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, CODE, DIV, H3, INPUT, LABEL, OPTION, P, SELECT, SPAN, TABLE, TBODY, TD, TH, THEAD, TR} = choc; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";
import {cmd_configure} from "$$static||command_editor.js$$";

//TODO: When we subscribe to a special, have the back end also send us the framework for it
cmd_configure({
	subscribe: "!!hyperlink",
	get_command_basis: command => {
		const basis = {type: "anchor_special"};
		set_content("#advanced_view h3", ["Edit special response ", CODE("!" + command.id.split("#")[0])]);
		const params = {"{username}": "Person who linked", "{uid}": "ID of that person"};
		basis._provides = {
			"{msg}": "The message that was posted",
			"{offense}": "0 if given a permit, else number of times they've posted links this stream"
		};
		basis._desc = "Happens when a hyperlink is posted";
		basis._shortdesc = "A hyperlink is posted";
		return basis;
	},
});

set_content("#settings", [
	TABLE([
		TR(TH({colSpan: 4}, "Who should be allowed to post links?")),
		TR([
			TD(LABEL([INPUT({type: "radio", id: "allowall"}), "Anyone (no filtering)"])),
			TD(LABEL([INPUT({type: "checkbox", disabled: true, checked: true}), "Mods"])),
			TD(LABEL([INPUT({type: "checkbox", name: "allowed", value: "vip"}), "VIPs"])),
			TD(LABEL([INPUT({type: "checkbox", name: "allowed", value: "raider"}), "Raiders"])),
			TD(LABEL([INPUT({type: "checkbox", name: "allowed", value: "permit"}), "!permit command"])),
		]),
	]),
	H3("Penalties"),
	P("First offense gets the first warning. Subsequent offenses will progress through the list. Take action and/or give a message."),
	TABLE([
		THEAD(TR([TH(), TH("Action"), TH("Message in chat"), TH()])),
		TBODY({id: "warnings"}),
	]),
	DIV({class: "buttonbox"}, [
		BUTTON({onclick: e => ws_sync.send({cmd: "addwarning"})}, "Add"),
	]),
	P([
		"Moderatorial actions should be done by which moderator? ",
		SELECT({id: "modvoice"}), BR(),
		"If the mod you want is missing or disabled, go to ",
		A({href: "voices"}, "Voices"),
		" to authenticate it - requires the ", CODE("Ban/timeout/unban users"), " permission.",
	]),
	P(["Want more flexibility? The ", BUTTON({"data-id": "!hyperlink", class: "advview"}, CODE("!!hyperlink")), " ", A({href: "specials"}, "special trigger"), " can do whatever you need, eg", BR(),
		"issuing warnings with the ", CODE("/warn"), " command to enforce that they be acknowledged."]),
	//TODO: Have a button that opens up the command editor for !!hyperlink
]);

export function render(data) {
	DOM("#allowall").checked = !data.blocked;
	const permitted = data.permit || [];
	document.querySelectorAll("[name=allowed]").forEach(el => el.checked = permitted.includes(el.value));
	set_content("#warnings", (data.warnings || []).map((warn, idx) => TR({"data-idx": idx}, [
		TD(idx + 1),
		TD([
			SELECT({name: "action", value: warn.action === "timeout" && warn.duration === 1 ? "purge" : warn.action || "warn"}, [
				OPTION({value: "warn"}, "No action"),
				OPTION({value: "delete"}, "Delete msg"),
				OPTION({value: "purge"}, "Purge"),
				OPTION({value: "timeout"}, "Timeout"),
				OPTION({value: "ban"}, "Ban"),
			]),
			SPAN({class: "timeout-duration"}, [" ", INPUT({name: "duration", type: "number", value: warn.duration || 60}), " sec"])
		]),
		TD(INPUT({name: "msg", size: 60, value: warn.msg})),
		TD(BUTTON({type: "button", class: "confirmdelete", title: "Delete"}, "🗑")),
	])));
	set_content("#modvoice", data.voices.map(v =>
		OPTION({value: v.id, disabled: !v.scopes.includes("moderator:manage:banned_users")}, v.desc))
	).value = data.voice;
}

//The radio button
on("click", "#allowall", e => {
	document.querySelectorAll("[name=allowed]").forEach(el => el.checked = false);
	ws_sync.send({cmd: "allow", all: 1});
});

//The check boxes
on("click", "[name=allowed]", e => {
	DOM("#allowall").checked = false;
	const msg = {cmd: "allow", all: 0, permit: []};
	document.querySelectorAll("[name=allowed]").forEach(el => el.checked && msg.permit.push(el.value));
	ws_sync.send(msg);
});

on("click", ".confirmdelete", simpleconfirm("Delete this warning level?", e => ws_sync.send({cmd: "delwarning", idx: e.match.closest_data("idx")})));

on("change", "#warnings input,#warnings select", e => ws_sync.send({cmd: "editwarning", idx: e.match.closest_data("idx"), [e.match.name]: e.match.value}));

on("change", "#modvoice", e => ws_sync.send({cmd: "configure", "voice": e.match.value}));
