# VLC integration

TODO: Show a list of current blocks and allow you to add/remove (and maybe reorder)

Each block is a regex to match on, and a description to be displayed.

Path | Description |
-----|-------------|-
-    | -

<ul id=unknowns></ul>

<script type=module>
import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BUTTON, INPUT, LI, TR, TD} = choc;

const blocks = $$blocks$$;
const unknowns = $$unknowns$$;

function make_block_desc(path, desc) {
	return TR([
		INPUT({value: path}),
		INPUT({value: desc}),
		BUTTON({type: "button", onclick: e => {
			console.log(e.closest("tr"));
		}}),
	]);
}

const tbody = DOM("table tbody");
blocks.forEach(b => tbody.appendChild(make_block_desc(b[0], b[1])));

set_content("#unknowns", unknowns.map(path => LI(A({href: "", onclick: e => {
	e.preventDefault();
	//console.log("TODO: New path ==>", path);
	tbody.appendChild(make_block_desc(path, ""));
}}, path))));
</script>
