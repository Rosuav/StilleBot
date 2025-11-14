import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, CODE, DIV, H3, INPUT, LABEL, OPTION, P, SELECT, TABLE, TBODY, TD, TH, THEAD, TR} = choc; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

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
	P("First offense gets the first warning. Subsequent offenses will progress through the list."),
	TABLE([
		THEAD(TR([TH(), TH("Action"), TH("Message in chat"), TH()])),
		TBODY({id: "warnings"}),
	]),
	DIV({class: "buttonbox"}, [
		BUTTON({class: "addwarning", "data-action": "warn"}, "Warning"),
		BUTTON({class: "addwarning", "data-action": "delete"}, "Delete message"),
		BUTTON({class: "addwarning", "data-action": "purge"}, "Purge chat messages"),
		BUTTON({class: "addwarning", "data-action": "timeout"}, "Timeout"),
		BUTTON({class: "addwarning", "data-action": "ban"}, "Ban"),
	]),
	P([
		"Moderatorial actions should be done by which moderator? ",
		SELECT({id: "modvoice"}), BR(),
		"If the mod you want is missing or disabled, go to ",
		A({href: "voices"}, "Voices"),
		" to authenticate it - requires the ", CODE("Ban/timeout/unban users"), " permission.",
	]),
]);

/* Also: Have a !!hyperlink special trigger, which is given all the necessary information. Suggest adding /warn to that. */

export function render(data) {
	DOM("#allowall").checked = !data.blocked;
	const permitted = data.permit || [];
	document.querySelectorAll("[name=allowed]").forEach(el => el.checked = permitted.includes(el.value));
	set_content("#warnings", (data.warnings || []).map((warn, idx) => TR({"data-idx": idx}, [
		TD(idx + 1),
		TD(
			warn.action === "ban" ? "Ban"
			: warn.action === "timeout" ? (
				warn.duration === 1 ? "Purge" : ["Timeout ", INPUT({name: "duration", type: "number", value: warn.duration}), " sec"]
			) : warn.action === "delete" ? "Delete message"
			: "Warning",
		),
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

on("click", ".addwarning", e => ws_sync.send({cmd: "addwarning", action: e.match.dataset.action}));

on("click", ".confirmdelete", simpleconfirm("Delete this warning level?", e => ws_sync.send({cmd: "delwarning", idx: e.match.closest_data("idx")})));

on("change", "#warnings input", e => ws_sync.send({cmd: "editwarning", idx: e.match.closest_data("idx"), [e.match.name]: e.match.value}));

on("change", "#modvoice", e => ws_sync.send({cmd: "configure", "voice": e.match.value}));
