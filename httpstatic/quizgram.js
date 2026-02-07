import {choc, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, B, BUTTON, DIV, FORM, IMG, INPUT, LABEL, LI} = choc; //autoimport

//<input maxlength=1 size=1 autocomplete=off>

//Code blocks containing underscores are shorthand for sets of inputs.
//Inside the heading, give them automatic linkages so we can reference them below.
let nextidx = 0;
for (let el of [...document.getElementsByTagName("code")]) {
	const attrs = {maxlength: 1, size: 1, autocomplete: "off", class: "ltr"};
	if (el.closest("h2")) attrs.readonly = "on"; else attrs["class"] = "ltr editable";
	el.replaceWith(...el.textContent.matchAll(/_|-\d+-/g).map(c => INPUT({
		...attrs, "data-linkage": attrs.readonly ? "-" + (++nextidx) + "-" : c[0],
	})));
}

//Jump from input to input within a group.
on("beforeinput", ".ltr", e => {
	if (e.inputType === "deleteContentBackward" && e.match.value === "") {
		const prev = e.match.previousElementSibling;
		if (prev && prev.tagName === "INPUT") prev.focus();
	}
});
on("input", ".ltr", e => {
	if (e.inputType === "insertText" && e.match.value.length === e.match.maxLength) {
		const next = e.match.nextElementSibling;
		if (next && next.tagName === "INPUT") next.focus();
	}
	const linkage = e.match.dataset.linkage;
	if (linkage !== "_") DOM('h2 input[data-linkage="' + linkage + '"]').value = e.match.value;
});

on("focusin", "h2 .ltr", e => {
	//TODO: Highlight the linked letter, and if there isn't one, make it clear to an admin that one's needed
	//Putting focus there isn't the best but it'll do for now
	const linked = DOM('.ltr.editable[data-linkage="' + e.match.dataset.linkage + '"]');
	if (linked) linked.focus();
});

//TODO: Save everything into localStorage, and have a button (with confirmation) to clear that
