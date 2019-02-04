# Commands for $$channel$$

The marker `$$$$` will be replaced with the name of the person entering the
command, and `%s` will take whatever text was added after the command name.

To remove a command or part of a command's output, just blank it.

$$messages$$

Command | Output |
--------|--------|-
$$commands$$

$$save_or_login$$

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
</script>
