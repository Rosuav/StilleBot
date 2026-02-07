import {choc, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, B, BUTTON, DIV, FORM, IMG, INPUT, LABEL, LI} = choc; //autoimport

//<input maxlength=1 size=1 autocomplete=off>

//Code blocks containing underscores are shorthand for sets of inputs.
for (let el of [...document.getElementsByTagName("code")]) {
	const attrs = {maxlength: 1, size: 1, autocomplete: "off", class: "ltr"};
	if (el.closest("h2")) attrs.readonly = "on";
	el.replaceWith(...el.textContent.split("").map(c => INPUT(attrs)));
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
});
