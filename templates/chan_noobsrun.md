# How far will $$channel$$ run?

<style>
input[type=number] {width: 4em;}
.preview-frame {
	border: 1px solid black;
	padding: 4px;
}
.preview-bg {padding: 6px;}
#preview div {width: 33%;}
#preview div:nth-of-type(2) {text-align: center;}
#preview div:nth-of-type(3) {text-align: right;}
</style>

<table border=1>
<tr><th>Variable</th><td><input size=20 name=varname></td></tr>
<tr><th>Current</th><td><input size=10 name=currentval><select name=milepicker></select><button type=button id=setval>Set</button><br>
	NOTE: This will override any donations! Be careful!
	<br>Changes made here are NOT applied with the Save button.
</td></tr>
<tr><th>Text</th><td><input size=60 name=text><br>Put a '#' where the mile count should go - it'll be replaced<br>with the actual number.</td></tr>
<tr><th>Cost per mile</th><td><input size=60 name=thresholds><br>eg "10 10 10 10 20 30 40 50" for slowly ramping up costs</td></tr>
<tr><th>Font</th><td>
	<input size=40 name=font><input name=fontsize type=number value=16>
	<select><option>TODO</option><option>normal</option><option>bold</option></select><br>
	Pick a font from Google Fonts or one that's<br>
	already on your PC. (Name is case sensitive.)
</td></tr>
<tr><th>Text color</th><td><input type=color name=color></td></tr>
<tr><th>Bar color</th><td><input type=color name=barcolor></td></tr>
<tr><th>Fill color</th><td><input type=color name=fillcolor></td></tr>
<tr><th>Needle size</th><td><input type=number name=needlesize min=0 max=1 step=0.005 value=0.375> Thickness of the red indicator needle</td></tr>
<tr><th>Custom CSS</th><td><textarea name=css></textarea></td></tr>
<tr><th>Preview</th><td><div id=preview></div></td></tr>
<tr><th>Link</th><td><a href="monitors?view=$$nonce$$" class=monitorlink>Drag me to OBS</a></td></tr>
</table>
<input type=submit value=Save>

<script>let channame = $$channame$$, nonce = "$$nonce$$", css_attributes = "$$css_attributes$$", info = $$info$$, sample = $$sample$$;</script>
<script type=module src="$$static||noobsrun.js$$"></script>
