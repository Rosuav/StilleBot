# $$title||Emote checklist$$

<style>
* {box-sizing: border-box;}
p {max-width: 80em; padding: 0.25em;}
figure {
	display: inline-block;
	margin: 0; padding: 0;
}
figcaption
{
	text-align: center;
	/* There's a bit of a gap above the caption, which seems wrong.
	Move that gap to the bottom instead. */
	margin-top: -0.25em;
	margin-bottom: 0.25em;
}
img {
	filter: saturate(0);
	border: 2px solid transparent;
	/* Some of the HypeUnicorn emotes aren't full size, so force them to 112x112 */
	width: 116px; height: 116px; /* == 112 plus two borders */
}
#showall:checked ~ figure img {filter: saturate(1);}
@media (max-width: 760px)
{
	img {
		border: 1px solid transparent;
		width: 58px; height: 58px;
	}
	figcaption {font-size: 50%;}
}
img:hover {filter: saturate(1);}
body.greyscale {filter: saturate(0);}
</style>

<style id=haveemotes>
img.have, $$emotes$$ {filter: saturate(1); border-color: green;}
</style>

$$login_link$$

$$text$$

<script type=module src="$$static||utils.js$$"></script>
