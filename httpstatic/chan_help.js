import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {} = choc; //autoimport

export function render(data) {
	DOM("#is_live").hidden = !data.online;
}

on("submit", "#whisperform", e => {
	e.preventDefault();
	ws_sync.send({cmd: "whisper", message: DOM("#whisper").value});
	DOM("#whisper").value = "";
});
