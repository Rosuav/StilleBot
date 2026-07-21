import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {B, BUTTON, H1, IMG, P} = lindt; //autoimport

export function render(data) {
	replace_content("main", [
		H1("Pages"),
		P("Build simple web pages and host them on GitHub Pages. You retain full control at all times, and can take over the site, move it to other hosting, etc, as your site grows."),
		P([
			"Your site is linked to your Twitch account. ",
			//If you're logged in, show who you are, and allow switching. Otherwise, invite a login.
			data.self && [
				IMG({src: data.self.profile_image_url, class: "avatar", style: "vertical-align: middle"}),
				" ", B(data.self.display_name), " ",
			],
			BUTTON({type: "button", class: "twitchlogin", "data-force": "1"}, data.self ? "Not you?" : "Log in with Twitch"),
		]),
		!data.site?.url ? P([
			//If there's no URL, either it hasn't loaded yet, or you don't have a repo.
			data.site?._last_checked ? [
				"You don't currently have a web site set up this way. Would you like to start one? ",
				BUTTON({type: "button", id: "createsite"}, "Create site!"),
			] : "Loading web site information...",
		]) : [
			//TODO: Show the deployed version, esp with its CNAME if present
			"You have a web site at ", A({href: data.site.url}, data.site.url),
		],
	]);
}
