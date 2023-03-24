import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {} = choc; //autoimport

on("input", "#original_url", e => {
	console.log("Parse this!", e.match.value);
});
