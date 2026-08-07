import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, B, BR, BUTTON, DETAILS, DIV, FORM, H3, IMG, INPUT, LI, P, SPAN, SUMMARY, UL} = lindt; //autoimport

let curscene = "";
let state = { };
let mutation_allowed = false; //If true, show buttons etc for read/write access, since the server's told us we're allowed to
export function sockmsg_mutation(msg) {mutation_allowed = msg.allowed; render(state);}

//Use &edit= to enable editing automatically. If a password has been set, this won't work.
//TODO: Allow the user to enter a password, which then gets saved here - on socket reconnect,
//the same password will be re-sent.
let mutate = new URLSearchParams(location.search).get("edit");
export function socket_connected(sock) {
	if (typeof mutate === "string") sock.send(JSON.stringify({cmd: "mutate", mutate}));
}

export function render(data) {
	if (data.allmocks) return replace_content("#allmockups", [
		data.allmocks.map(m => LI(A({href: "mockup?view=" + m.id}, m.title))), //TODO: Show creation date?
		!data.allmocks.length && LI("(none)"),
	]);
	state = data; //Yes, this will include state.cmd == "update", no big deal
	if (state.scenes && !state.scenes[curscene]) {
		//You aren't on any scene. Pick one. TODO: Have a "default scene" selector somewhere.
		curscene = Object.keys(state.scenes)[0];
	}
	//repaint(); //when we have a canvas
}

on("click", "#create_mockup", e => ws_sync.send({cmd: "create_mockup"}));
