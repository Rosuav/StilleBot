import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {} = choc; //autoimport

export function render(data) {
}

on("submit", "#kofitoken", e => {
	e.preventDefault();
	ws_sync.send({cmd: "settoken", token: e.match.elements.token.value});
	e.match.elements.token.value = "";
});
