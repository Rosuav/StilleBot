import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, FORM, IMG, INPUT, LI, STRONG, TD, TR} = choc; //autoimport

export function render(data) {
	//Note that the entire token will never be shown, only the last few characters
	if (data.kofitoken) DOM("#kofitoken").value = data.kofitoken;
	if (data.kofitokens) set_content("#kofitokens table tbody", [
		data.kofitokens.map(tok => TR([
			TD(FORM({class: "token", id: "kofitokform" + tok.label, "data-platform": "kofi"}, [
				INPUT({type: "hidden", name: "prevlabel", value: tok.label}),
				INPUT({size: 8, readonly: true, disabled: true, value: tok.label}),
			])),
			TD(INPUT({form: "kofitokform" + tok.label, name: "token", size: 40, value: tok.token})),
			TD(BUTTON({form: "kofitokform" + tok.label, type: "submit"}, "Save")),
		])),
		TR([
			TD(FORM({class: "token", id: "kofitokform", "data-platform": "kofi"}, [
				INPUT({type: "hidden", name: "prevlabel", value: ""}),
				INPUT({name: "label", size: 8, required: true}),
			])),
			TD(INPUT({form: "kofitokform", name: "token", size: 40})),
			TD(BUTTON({form: "kofitokform", type: "submit"}, "Add")),
		]),
	]);
	if (data.fwshopname) set_content("#fwstatus", [
		"Your Fourth Wall shop is: ",
		A({href: "https://" + data.fwurl}, data.fwshopname),
		" Welcome, ", data.fwusername, ". ",
		BUTTON({id: "fwlogin"}, "Reauthenticate"),
	]);
	if (data.paturl) set_content("#patreonstatus", [
		"Your Patreon campaign is: ",
		A({href: data.paturl}, data.paturl),
		" ",
		BUTTON({id: "resyncpatreon", type: "button"}, "Resync supporters"),
	]);
}

on("submit", ".token", e => {
	e.preventDefault();
	const msg = {cmd: "settoken", platform: e.match.dataset.platform};
	for (const el of e.match.elements) if (el.name) {msg[el.name] = el.value; el.value = "";}
	ws_sync.send(msg);
});

on("click", "#fwlogin", e => ws_sync.send({cmd: "fwlogin"}));

on("click", "#patreonlogin", e => {
	e.preventDefault();
	ws_sync.send({cmd: "patreonlogin"});
});

export function sockmsg_oauthpopup(msg) {
	window.open(msg.uri, "login", "width=525, height=900");
}

on("click", "#resyncpatreon", e => ws_sync.send({cmd: "resyncpatreon"}));

export function sockmsg_resyncpatreon(msg) {
	set_content("#patrons", msg.members.map(mem => LI([
		//We might not have Twitch connected, but we should at least have a name.
		STRONG(mem.name),
		" is paying ",
		//FIXME: What about other currencies? Here assuming that everything is some sort of dollar.
		STRONG(new Intl.NumberFormat("en-US", {style: "currency", currency: "USD"}).format(mem.price / 100)),
		" per month. ",
		mem.twitch && A({href: "https://twitch.tv/" + mem.twitch.login, target: "_blank"}, [
			IMG({src: mem.twitch.profile_image_url, class: "avatar"}),
			" ",
			mem.twitch.display_name,
		]),
	])));
	DOM("#patrondlg").showModal();
}
