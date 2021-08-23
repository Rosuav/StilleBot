import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {BR, BUTTON, INPUT, TR, TD} = choc;
import {add_hook, open_advanced_view, sockmsg_validated, sockmsg_loadfavs, favcheck, render_command, commands} from "$$static||command_editor.js$$";
export {add_hook, open_advanced_view, sockmsg_validated, sockmsg_loadfavs, favcheck};

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
export const render_item = render_command;
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
