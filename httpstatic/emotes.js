import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const { } = choc;

async function upload(file) {
	set_content("#emotetips", "Analyzing...");
	const resp = await (await fetch("emotes?checkfile", {
		method: "POST",
		body: file,
		credentials: "same-origin",
	})).json();
	if (resp.error) return set_content("#emotetips", DIV({class: "error"}, resp.error));
	console.log("Uploaded!", resp);
}

on("change", "input[type=file]", e => {
	for (let f of e.match.files) upload(f);
	e.match.value = "";
});
on("dragover", ".filedropzone", e => e.preventDefault());
on("drop", ".filedropzone", e => {
	e.preventDefault();
	for (let f of e.dataTransfer.items) upload(f.getAsFile());
});
