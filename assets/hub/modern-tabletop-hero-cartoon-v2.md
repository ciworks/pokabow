# Modern Tabletop hub hero — cartoon v2

- Created: 2026-10-17 using the built-in imagegen tool.
- Runtime asset: [modern-tabletop-hero-cartoon-v2.png](modern-tabletop-hero-cartoon-v2.png).
- Direction: [Design system, avatars and graphics](../../docs/DESIGN_SYSTEM.md#avatars-and-graphics).
- Style reference: [original approved concept](../../docs/design/modern-tabletop-reference.png).
- Replaces: modern-tabletop-hero.png, whose semi-realistic people were rejected.
- Integration: the hub scene references this asset; layout and navigation are unchanged.

Characters are intentionally simplified 2D cartoons: expressive large eyes,
rounded faces, broad hair and beard shapes, clean contours and limited shading.
Existing user-uploaded photos and the gameplay tile painter are unaffected.

The two references used for generation were the original approved three-screen
concept (style authority) and the first hub hero (composition/edit target only).
The result was visually reviewed before integration. It is decorative artwork,
not authoritative game-state or scoring data.

## Exact generation prompt

Use case: style-transfer. Asset: replacement Pokabow mobile hub hero illustration with true transparent background.
IMAGE ROLES: Image 1 (the three-screen POKABOW design board) is the APPROVED CHARACTER STYLE reference. Specifically match the small friendly cartoon woman and man in the home screen and the cartoon portraits on the profile screen. Image 2 (existing large hero illustration) is the EDIT TARGET for composition only; its semi-realistic faces are rejected.

Reillustrate image 2 in the clearly CARTOONY 2D illustrated character style of image 1. This is an important style correction. The people must look like simplified hand-drawn casual-game avatars: large expressive eyes, simplified small noses, rounded face silhouettes, expressive smiles, bold clean drawn contours, grouped graphic hair curls/locks rather than strands, flat colour fills and only one or two simple cel-shaded shapes. Bodies/clothes simplified graphic shapes. ZERO realistic skin shading, ZERO pores, ZERO photographic texture, ZERO realistic beard hairs, ZERO painterly portrait rendering or 3D human rendering. Match the playful cartoon abstraction of the reference, not lifelike adults. Both figures should clearly look like cartoon characters even at 48px size.

Maintain general composition and subject identity: left brown-skinned cartoon woman with dark curly hair and sage shirt inside peach circular medallion, right cheerful cartoon man with brown hair and a simplified single-shape short beard and teal shirt inside sage medallion. Three central overlapping square ivory poker tiles: A black spade on left, K red heart in center, Q black club on right. Each tile has four discrete solid-colour edge bands, one per edge, from blue #0072B2, vermilion #D55E00, green #009E73 and yellow #F0E442. Tile ranks exactly A K Q, no additional text. Keep tiles softly tactile, with only subtle short shadows. Quiet soft sage ellipse behind the tiles, two or three small teal drawn emphasis strokes. Keep portraits and tiles similar proportions to the original design board's home illustration, faces not dominating tiles.

Palette: ivory #F6F2E9, deep teal #173D42, sage #DFEAE4, honey #F4C86A, peach #F4BC9E. Landscape 3:2 composition. Full illustration visible with small clear margin. Transparent outside the illustration silhouette: no black background, no large shadow halo, no fog, no global vignette, no photographic lighting. No UI, phone, heading, buttons, or border. Output only the isolated production-ready hero asset, not a design board.

## Integration verification

Godot 4.6 rendered hub checks passed: 340 assertions, zero failures. The revised character art was visually inspected in the actual hub at 540x960. Physical-device testing remains outstanding.
