# Otto, the Hour Tracker owl

`otto-master.png` is the approved master sheet (OpenArt resource `tmH4DhdkHzzFR6YsSs24`, GPT Image 2.5 Sunburst). Its three poses are `idle`, `wave` and `cheer`. Every other pose was made with image2image from that sheet, three poses per sheet, 16:9, medium quality.

## Prompt used for every pose sheet

> Using the reference image, keep this exact owl character, named Otto: same caramel-brown body and wings, cream heart-shaped face disc, round amber eyes with small white highlights, small orange beak and feet, violet knit scarf with ribbed hanging end, light chevron feather marks on the cream belly, identical proportions and the same flat 2D vector style with simple flat shading and no outlines. Draw a new character sheet with three new poses of Otto side by side, evenly spaced, each the same size as in the reference: (1) … (2) … (3) …. Props use simple flat colors and are never violet. Plain solid near-black background #0F0F14, a soft flat dark ellipse under each pose, no text, no letters, no logos.

Props must never be violet, because violet is how the scarf layer is found. Keep the background `#0F0F14`, because that's the colour `cut_sheet.py` keys out.

## Pose descriptions

| Pose | Description |
|---|---|
| coffee | holding a plain white coffee mug with a small curl of steam in both wings |
| clipboard | holding a brown clipboard with white paper and a yellow pencil, reading |
| sleep | sleeping on a pale-yellow crescent moon, eyes closed |
| trophy | holding a gold trophy up high, eyes squinted, cheering |
| streak | beside a flat orange flame, fist-pump |
| crown | small gold crown, wings on hips |
| buddies | high-fiving a smaller grey-brown owl with a teal scarf |
| heart | hugging a coral-red heart |
| search | peering through a gold magnifying glass |
| wrench | silver wrench on the shoulder |
| calendar | holding a calendar page with a coral top bar |
| bell | ringing a gold hand bell |
| shield | holding a mint shield with a white check |
| pin | holding a coral map pin like a flag |
| shades | dark sunglasses, wings crossed |
| peek | head, scarf and wing tips over a straight bottom edge |
| oops | sheepish, scratching head, light-blue sweat drop |
| point | pointing right, other wing on hip |

## Adding or redoing a pose

1. Generate a sheet with the prompt above.
2. Cut the pose out:
   `python3 scripts/mascot/cut_sheet.py sheet.png <index 0-2> <pose>.png`
3. Vectorize it and install it into the asset catalog:
   `python3 scripts/mascot/build_otto.py <pose> <pose>.png`
4. Add the case to `OwlPose`.
