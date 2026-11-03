# Built-in imagegen prompt set

## Existing cell cleanup
Use case: precise-object-edit. Remove only detached magic feathers, petals, stars, sparkles, pink/gold aura and free silk ribbon loops from the exact approved cell. Preserve the complete clothed Retto and Finn, actual head bow and gold tails, costume cords and skirt, actual Finn wings, chest Rosario, exact gesture, face, blue eyes, body/Finn scale, four-limb pattern, paw positions, tail and canvas registration. Restore only cloth or fur hidden by VFX. No separate limb or garment compositing, no recentering/cropping/zooming. Transparent background.

Running cells explicitly preserve one raised front paw, one grounded cuffed front paw and two small bare rear paws. Existing drag cells preserve the original eight gait poses. Targeted follow-ups remove remaining floating pink jewels near the raised paw, transparency noise on running 04, and isolated feathers above Finn on waving 00–02.

## Effect assets
- Ivory curved feather: soft plush/satin texture, blush-pink edge and warm gold shaft, isolated transparent cutout.
- Scarlet S ribbon: satin with ivory reverse and thin gold piping, isolated transparent cutout.
- Front ribbon arc: one wide shallow U-shaped scarlet satin ribbon, gold piping and ivory reverse, approximately 4:1 width/height, believable folds and tapered ends; no stacked stripes or bow.
- Wing fan: two ivory feather wing fans, shallow V with open centre, five layered feathers each, soft blush bases and pearl/gold edge light; no character, ribbon, medallion or background.

All art used the built-in imagegen tool. Raster effect assets are independently animated and exported by build-effects.cjs; character poses are not warped or translated for effect production.
