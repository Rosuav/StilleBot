import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, LI, OPTION} = lindt; //autoimport

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

function EDITBUTTON(cat, id) {
	return BUTTON({class: "editelement", "data-cat": cat, "data-element": id},
		mutation_allowed ? "🖉" : "📄"); //It's the same button, but if mutation's not allowed, don't imply the potential to edit
}

export function render(data) {
	if (data.allmocks) return replace_content("#allmockups", [
		data.allmocks.map(m => LI(A({href: "mockup?view=" + m.id, target: "_blank"}, m.title))), //TODO: Show creation date?
		!data.allmocks.length && LI("(none)"),
	]);
	state = data; //Yes, this will include state.cmd == "update", no big deal
	if (state.scenes && !state.scenes[curscene]) {
		//You aren't on any scene. Pick one. TODO: Have a "default scene" selector somewhere.
		curscene = Object.keys(state.scenes)[0];
	}
	//This feels inefficient. Doing all this work every time anything changes, when it only
	//needs to be updated when a scene is added/removed/renamed, seems like overkill. *sigh*
	replace_content("#sceneselector",
		Object.entries(state.scenes).map(e => [e[0], e[1].title])
		.sort((a, b) => a[1].localeCompare(b[1]))
		.map(e => OPTION({value: e[0]}, e[1]))
	).value = curscene;
	replace_content("#scenebuttons", [
		EDITBUTTON("scenes", curscene),
		mutation_allowed && BUTTON({id: "new_scene", title: "Add new scene"}, "+"),
	]);
	DOM("#editelementdlg [type=submit]").hidden = !mutation_allowed;
	replace_content("#editelementdlg h3", mutation_allowed ? "Edit element" : "Element details");
	DOM("#elementtitle").readOnly = !mutation_allowed;
	DOM("#elementdesc").readOnly = !mutation_allowed;
	if (state.title) replace_content("#mockups", [ //This is the "# Mockups" default heading :)
		state.title, " ", EDITBUTTON("mockup", ""),
	]);
	//repaint(); //when we have a canvas
}

on("change", "#sceneselector", e => {curscene = e.match.value; render(state);});

on("click", "#create_mockup", e => ws_sync.send({cmd: "create_mockup"}));
export function sockmsg_mockup_created(msg) {
	window.open("/mockup?view=" + msg.id + "&edit=", "_blank");
}

let editing_cat = null, editing_element = null;
on("click", ".editelement", e => {
	editing_cat = e.match.dataset.cat;
	editing_element = e.match.dataset.element;
	const elem =
		editing_cat === "mockup" ? state //Category "mockup" has no ID, you are editing the mockup as a whole
		: state[editing_cat][editing_element]; //Otherwise the cat is a key within the state, eg "elements" or "scenes"
	DOM("#elementtitle").value = elem.title || "";
	DOM("#elementdesc").value = elem.description || "";
	DOM("#editelementdlg").showModal();
});

on("submit", "#editelementdlg form", e => ws_sync.send({cmd: "update_element",
	cat: editing_cat, id: editing_element,
	title: DOM("#elementtitle").value,
	description: DOM("#elementdesc").value,
}));

on("click", "#new_scene", e => ws_sync.send({cmd: "new_scene"}));
export function sockmsg_select_scene(msg) {curscene = msg.id;} //Will take effect next update (which should be following shortly)
