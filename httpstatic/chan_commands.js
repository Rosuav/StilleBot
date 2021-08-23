import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {BR, BUTTON, CODE, INPUT, TR, TD} = choc;
import {add_hook, open_advanced_view, sockmsg_validated, sockmsg_loadfavs, favcheck} from "$$static||command_editor.js$$";
export {add_hook, open_advanced_view, sockmsg_validated, sockmsg_loadfavs, favcheck};
const commands = { };

on("click", "button.addline", e => {
	let parent = e.match.closest("td").previousElementSibling;
	parent.appendChild(BR());
	parent.appendChild(INPUT({className: "widetext"}));
});

on("click", "button.advview", e => {
	const tr = e.match.closest("tr");
	open_advanced_view(commands[tr.dataset.editid || tr.dataset.id]);
});

on("click", 'a[href="/emotes"]', e => {
	e.preventDefault();
	window.open("/emotes", "emotes", "width=900, height=700");
});

on("click", "#examples", e => {
	e.preventDefault();
	document.getElementById("templates").showModal();
});
on("click", "#templates tbody tr", e => {
	e.preventDefault();
	document.getElementById("templates").close();
	const [cmd, text] = e.match.children;
	const cmdname = cmd.innerText.trim();
	const template = complex_templates[cmdname];
	if (template) {
		open_advanced_view({...template, id: cmdname.slice(1)});
		if (cmdname[0] === '!') set_content("#cmdname", INPUT({value: cmdname}));
		else set_content("#cmdname", "");
		return;
	}
	DOM("#newcmd_name").value = cmdname;
	DOM("#newcmd_resp").value = text.innerText.trim();
});

export const render_parent = DOM("#commandview tbody");
function collect_messages(msg, cb, pfx) {
	if (typeof msg === "string") cb(pfx + msg);
	else if (Array.isArray(msg)) msg.forEach(line => collect_messages(line, cb, pfx));
	else if (typeof msg !== "object") return; //Not sure what this could mean, but we can't handle it. Probably a null entry or something.
	else if (msg.conditional && msg.otherwise) { //Hide the Otherwise if there isn't any (either a normal command with "" or a trigger with undefined)
		collect_messages(msg.message, cb, pfx + "?) ");
		collect_messages(msg.otherwise, cb, pfx + "!) ");
	}
	else collect_messages(msg.message, cb, pfx);
}
export function render_item(msg) {
	//All commands are objects with (at a minimum) an id and a message.
	//A simple command is one which is non-conditional, and whose message  is either
	//a string or an array of strings. Anything else is a non-simple command and will
	//be non-editable in the table - it can only be edited using the Advanced View popup.
	const response = [], cmd = msg.id.split("#")[0];
	let addbtn = "";
	let editid = msg.id;
	if (msg.alias_of) {
		response.push(CODE("Alias of !" + msg.alias_of), BR());
		editid = msg.alias_of + "#" + msg.id.split("#")[1];
	}
	else if (!msg.conditional && (
		typeof msg.message === "string" ||
		(Array.isArray(msg.message) && !msg.message.find(r => typeof r !== "string"))
	)) {
		//Simple message. Return an editable row.
		collect_messages(msg.message, m => response.push(INPUT({value: m, className: "widetext"}), BR()), "");
		addbtn = BUTTON({type: "button", className: "addline", title: "Add another line"}, "+");
	}
	else {
		//Complex message. Return a non-editable row.
		collect_messages(msg, m => response.push(CODE(m), BR()), "");
	}
	response.pop(); //There should be a BR at the end.
	commands[msg.id] = msg;
	return TR({"data-id": msg.id, "data-editid": editid}, [
		TD(CODE("!" + cmd)),
		TD(response),
		TD([
			BUTTON({type: "button", className: "advview", title: "Advanced"}, "\u2699"),
			addbtn,
		]),
	]);
}
export function render(data) {
	favcheck();
	if (DOM("#addcmd")) render_parent.appendChild(DOM("#addcmd").closest("TR")); //Move to end w/o disrupting anything
	else render_parent.appendChild(TR([
		TD(["Add: ", INPUT({id: "newcmd_name", size: 10, placeholder: "!hype"})]),
		TD(INPUT({id: "newcmd_resp", className: "widetext"})),
		TD(BUTTON({type: "button", id: "addcmd"}, "Add")),
	]));
}
on("input", "tr[data-id] input", e => e.match.closest("tr").classList.add("dirty"));

on("submit", "main > form", e => {
	e.preventDefault();
	document.querySelectorAll("tr.dirty[data-id]").forEach(tr => {
		const msg = [];
		tr.querySelectorAll("input").forEach(inp => inp.value && msg.push(inp.value));
		if (!msg.length) {
			ws_sync.send({cmd: "delete", cmdname: tr.dataset.id});
			return;
		}
		const response = {message: msg};
		//In order to get here, we had to render a simple command. That means its
		//message is pretty much all there is to it, but there might be some flags.
		const prev = commands[tr.dataset.id];
		for (let flg in flags) if (prev[flg]) response[flg] = prev[flg];
		ws_sync.send({cmd: "update", cmdname: tr.dataset.id, response});
		//Note that the dirty flag is not reset. A successful update will trigger
		//a broadcast message which, when it reaches us, will rerender the command
		//completely, thus effectively resetting dirty.
	});
	addcmd();
});
function addcmd() {
	const newcmd = DOM("#newcmd_name");
	if (newcmd) { //Applicable only to the main command editor
		const cmdname = newcmd.value, response = DOM("#newcmd_resp").value;
		if (cmdname !== "" && response !== "") {
			ws_sync.send({cmd: "update", cmdname, response});
			newcmd.value = DOM("#newcmd_resp").value = "";
			newcmd.closest("tr").classList.remove("dirty");
		}
	}
}
on("click", "#addcmd", addcmd); //Note that there'll never be more than one add button at the moment, but might be zero.
