import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {PRE} = choc; //autoimport

export function render(data) {
	if (data.raw) set_content("#nextad", PRE(JSON.stringify(data.raw)));
}

on("click", "#snooze", e => ws_sync.send({cmd: "snooze"}));
