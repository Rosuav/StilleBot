import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, IMG, LI, STRONG} = choc; //autoimport

export function render(data) {
	//Note that the entire token will never be shown, only the last few characters
	if (data.kofitoken) DOM("#kofitoken").value = data.kofitoken;
	if (data.fwtoken) DOM("#fwtoken").value = data.fwtoken;
	if (data.paturl) set_content("#patreonstatus", [
		"Your Patreon campaign is: ",
		A({href: data.paturl}, data.paturl),
		" ",
		BUTTON({id: "resyncpatreon", type: "button"}, "Resync supporters"),
	]);
}

on("submit", ".token", e => {
	e.preventDefault();
	ws_sync.send({cmd: "settoken", token: e.match.elements.token.value, platform: e.match.dataset.platform});
	e.match.elements.token.value = "";
});

on("click", "#patreonlogin", e => {
	e.preventDefault();
	ws_sync.send({cmd: "patreonlogin"});
});

export function sockmsg_patreonlogin(msg) {
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
