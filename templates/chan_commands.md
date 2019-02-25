# Commands for $$channel$$

The marker `$$$$` will be replaced with the name of the person entering the
command, and `%s` will take whatever text was added after the command name.

To remove a command or part of a command's output, just blank it.

$$messages$$

Command | Output |
--------|--------|-
$$commands$$

$$save_or_login$$

> dialog id=templates
>
> Command | Text
> --------|------
> $$templates$$
>
> Be sure to customize the command text to suit your channel, lest your commands
> look identical to everyone else's :)

<script>
document.querySelectorAll("button").forEach(btn => btn.onclick = e => {
	const inp = document.createElement("input");
	inp.name = e.currentTarget.name;
	inp.size = 200;
	const parent = e.currentTarget.parentElement;
	parent.removeChild(e.currentTarget);
	parent.appendChild(document.createElement("br"));
	parent.appendChild(inp);
});
document.getElementById("examples").onclick = e => {
	e.preventDefault();
	document.getElementById("templates").showModal();
};
document.querySelectorAll("#templates tbody tr").forEach(tr => tr.onclick = e => {
	document.getElementById("templates").close();
	const [cmd, text] = e.currentTarget.children;
	document.forms[0].newcmd_name.value = cmd.innerText;
	document.forms[0].newcmd_resp.value = text.innerText;
});

//Compat shim lifted from Mustard Mine
//For browsers with only partial support for the <dialog> tag, add the barest minimum.
//On browsers with full support, there are many advantages to using dialog rather than
//plain old div, but this way, other browsers at least have it pop up and down.
document.querySelectorAll("dialog").forEach(dlg => {
	if (!dlg.showModal) dlg.showModal = function() {this.style.display = "block";}
	if (!dlg.close) dlg.close = function() {this.style.removeProperty("display");}
});
</script>

<style>
#templates tbody tr:nth-child(odd) {
	background: #eef;
	cursor: pointer;
}

#templates tbody tr:nth-child(even) {
	background: #eff;
	cursor: pointer;
}

#templates tbody tr:hover {
	background: #ff0;
}
</style>
