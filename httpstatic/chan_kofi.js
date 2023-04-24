import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {} = choc; //autoimport

export function render(data) {
	//Note that the entire token will never be shown, only the last few characters
	if (data.token) document.forms.kofitoken.elements.token.value = data.token;
}

on("submit", "#kofitoken", e => {
	e.preventDefault();
	ws_sync.send({cmd: "settoken", token: e.match.elements.token.value});
	e.match.elements.token.value = "";
});
