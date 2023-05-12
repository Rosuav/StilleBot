import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, DIV, IMG, INPUT, LABEL, LI, SPAN, TD, TEXTAREA, TR} = choc; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

export const render_parent = DOM("#voices tbody");
export function render_item(item, mode) {
	//item.last_auth_time and (possibly) item.last_error_time - if auth < error,
	//suggest reauthenticating
	const botvoice = DOM(`#voices thead [data-id="${item.id}"]`);
	if (botvoice) botvoice.replaceWith();
	return TR({"data-id": item.id}, [
		TD([IMG({src: item.profile_image_url, className: "avatar"}), item.name]),
		TD(INPUT({value: item.desc, className: "desc", size: 15})),
		TD(TEXTAREA({value: item.notes || "", className: "notes", rows: 3, cols: 50})),
		mode === "botvoice" ? TD([
			DIV([
				//Activating voices can only be done with proper authentication.
				can_activate === "any" || can_activate === item.id
					? BUTTON({type: "button", class: "activate"}, "Activate")
					: "Contact the administrator to request access to this voice.",
			]),
		]) : TD([
			DIV([
				BUTTON({type: "button", className: "save"}, "Save"),
				BUTTON({type: "button", className: "delete"}, "Delete"),
				BUTTON({type: "button", class: "perms", "data-scopes": item.scopes.join("/")}, "Permissions"),
				BUTTON({type: "button", class: "makedefault"}, "Make default"),
			]),
			DIV({class: "isdefault"}, [
				"This is the default voice for this channel. ",
				BUTTON({type: "button", class: "unsetdefault"}, "Unset default"),
			]),
		]),
	]);
}
export function render_empty() {
	return render_parent.appendChild(TR([
		TD({colSpan: 4}, "No active voices."), //Won't normally be shown if there's a global default voice
	]));
}
let defvoice = "0";
export function render(data) {
	if (data.defvoice !== undefined) defvoice = data.defvoice;
	render_parent.querySelectorAll("[data-id]").forEach(tr => {
		tr.classList.toggle("defaultvoice", tr.dataset.id === defvoice);
	});
	//If there are any bot voices that aren't already authenticated, list them too, with option to add them.
	if (data.botvoices) data.botvoices.forEach(bv => {
		if (DOM(`[data-id="${bv.id}"]`)) return; //Already got this voice, possibly from a previous render or from having it on the channel
		DOM("#voices thead").appendChild(render_item(bv, "botvoice"));
	});
}

export function sockmsg_login(data) {window.open(data.uri, "login", "width=525, height=900");}

on("click", ".makedefault", e => {
	ws_sync.send({cmd: "update", id: e.match.closest("tr").dataset.id, makedefault: 1});
});

on("click", ".unsetdefault", e => {
	ws_sync.send({cmd: "update", unsetdefault: 1});
});

on("click", ".activate", e => {
	ws_sync.send({cmd: "activate", id: e.match.closest("tr").dataset.id});
});

on("click", ".save", e => {
	const tr = e.match.closest("tr");
	const msg = {cmd: "update", id: tr.dataset.id};
	msg.desc = tr.querySelector(".desc").value;
	msg.notes = tr.querySelector(".notes").value;
	ws_sync.send(msg);
});

on("click", ".delete", simpleconfirm("Deactivate this voice? Reactivating will require authentication.", e => {
	ws_sync.send({cmd: "delete", id: e.match.closest("tr").dataset.id});
}));

let perms_voiceid = null;
on("click", ".perms", e => {
	perms_voiceid = e.match.id !== "addvoice" && e.match.closest("tr").dataset.id;
	const scopes = (e.match.dataset.scopes || "").split("/");
	//Hack: Include chat_login in "additional" scopes
	additional_scopes.chat_login = "Regular messages and /me";
	set_content("#scopelist", [
		Object.entries(additional_scopes).sort().map(([scope, desc]) => LI(LABEL([
			scopes.includes(scope) ? "[Available] " : INPUT({type: "checkbox", name: scope, checked: scope === "chat_login"}),
			desc[0] === '*' && SPAN({class: "warningicon"}, "⚠️"),
			" ", desc.replace("*", ""), //should really just be a prefix removal
		]))),
	]);
	DOM("#permsdlg").showModal();
});

on("click", "#authenticate", e => {
	const scopes = [];
	document.querySelectorAll("#scopelist input:checked").forEach(cb => scopes.push(cb.name));
	ws_sync.send({cmd: "login", voiceid: perms_voiceid, scopes});
});
