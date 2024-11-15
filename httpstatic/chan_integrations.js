import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {} = choc; //autoimport

export function render(data) {
	//Note that the entire token will never be shown, only the last few characters
	if (data.kofitoken) DOM("#kofitoken").value = data.kofitoken;
	if (data.fwtoken) DOM("#fwtoken").value = data.fwtoken;
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
