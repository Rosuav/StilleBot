import collections
import subprocess
import requests
FONTS = "Lexend", "Noto+Emoji", "Noto+Sans+Symbols+2"

r = requests.get("https://fonts.googleapis.com/css?family=" + "|".join(FONTS), headers={"User-Agent": "Mozilla/5.0 Firefox/90.0"})
r.raise_for_status()
avail = collections.defaultdict(list)
seen = set()
for line in r.text.split("\n"):
	if ":" not in line: continue
	key, val = line.split(":", 1)
	if key.strip() == "font-family":
		font = val.strip(" ;'")
		if font not in seen:
			print("Scanning font", font)
			seen.add(font)
	if key.strip() == "unicode-range":
		for rng in val.strip(" ;").split(","):
			rng = rng.strip(" U+")
			# A codepoint range could be a single codepoint U+nnnn,
			# a wildcard range U+nn?? (assuming here that the wildcards are at the end??),
			# or a start and stop (inclusive?) separated by commas.
			if rng.endswith("?"):
				# Untested, doesn't seem to be used by Google Fonts anyway
				print(font, "USES WILDCARD RANGES")
				pfx = rng.strip("?")
				num = len(rng) - len(pfx)
				rng = pfx + "0" * num + "-" + pfx + "f" * num
			if "-" not in rng: rng += "-" + rng
			start, end = rng.split("-")
			for c in range(int(start, 16), int(end, 16) + 1):
				avail[c].append(font)

for c in "🖉⯇⣿":
	print("U+%04X" % ord(c), c, avail[ord(c)])
	subprocess.run(["fc-list", ":charset=" + hex(ord(c))])
