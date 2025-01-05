import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {} = choc; //autoimport
import {simpleconfirm} from "./utils.js";

export function render(data) {
	if (data.nonce) DOM("#obslink").href = "obs?key=" + data.nonce;
}

on("click", "#resetkey", simpleconfirm("Revoking the key will replace it with a new key, disabling the old one. Do it?", e =>
	ws_sync.send({cmd: "resetkey"})
));
