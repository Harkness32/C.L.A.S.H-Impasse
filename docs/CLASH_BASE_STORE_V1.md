# C.L.A.S.H. base store v1

A browser-based buy menu at every established base, replacing the arsenal
screen for players who want one list with search, previews and a cart.

Ported from Front Line Operations' store, which is built the same way. The
interface approach, the SQF/JS message shape and the preview trick are FLO's;
the catalog source, the pricing model and the base/authority integration are
C.L.A.S.H.'s and share nothing with it.

## Doctrine

The store is a **presentation and delivery surface**. It is not a resource
authority.

- Impasse remains the strategic authority. The store never touches campaign
  progression, objectives, tickets, HAL tasking or the Checkbook.
- `ITW_VEH_CURR_TICKETS` is an **AI spawn budget** and the store does not read
  or spend it. A player buying a truck does not compete with HAL for one.
- The store does not invent a catalog. It reads the two pools the mission
  already maintains, so every faction, DLC and map restriction already applied
  by `CustomArsenal_Arsenal` and `VehicleArrays.sqf` is inherited.
- The server owns every price, balance and delivery decision. The client sends
  intent only.

## Why it is a web page

The interface is a single `CT_WEBBROWSER` control (type 106) filling the safe
zone, rendering `ui\html\store.html`. **This requires Arma 3 2.20 or newer**
for the control, and 2.18 for `toJSON`/`fromJSON`.

The control is transparent (`colorBackground[] = {0,0,0,0}`) and the page leaves
a gap where `#previewViewport` sits. A real camera, mannequin and light are
created locally behind the page and framed to that gap, so the 3D preview is
the game engine seen through a hole in the UI, not anything the page draws.

**Vehicles are previewed as real local objects, gear as simple objects.** This
is not an arbitrary split. A simple object has no simulation, so
`TransportPylonsComponent` never initialises and every dynamic-loadout aircraft
renders with bare hardpoints — no missiles, no pods, no rotor or light state.
FLO's store has this bug; previewing vehicles with `createVehicleLocal` fixes
it. The ordering in `ITW_CLASH_Store_fnc_PreviewSelect` is load-bearing: the
config's default pylon attachments are applied while the vehicle initialises,
so simulation is switched off only afterwards. Disable it first and the pylons
are empty again. Gear keeps the cheaper simple-object path, having no
simulation to gain.

A useful side effect of the asset loader: with `A3API` absent it falls back to
ordinary relative `<link>`/`<script>` tags, so **`ui/html/store.html` opens in a
desktop browser** and the layout can be worked on without launching Arma. Only
the data is missing.

## Contract

- Available at the nearest **established** base of `ITW_PlayerSide` within
  `ITW_CLASH_StoreAccessRange` (80 m), from a self scroll action, the
  Communication menu (`CfgCommunicationMenu >> ITW_CLASH_StoreCommMenu` in
  `description.ext`, added with `[unit, class] call BIS_fnc_addCommMenuItem`),
  and an ACE self action when ACE is loaded. All three live on the unit, so
  they are installed once per unit the player becomes, respawns included
  (`ITW_CLASH_Store_fnc_InstallEntryPoints`, as the Job Channels menu does).
  The first test (2026-10-17) found the Communication menu entry called as
  `[class, [text, code]]`, which logged "Type String, expected Object" and
  added nothing, and the entry points added to the first body only.
- Range, liveness, side and base state are re-validated **on the server** for
  every request, not just when the menu opens.
- Every request is checked against `remoteExecutedOwner` so one client cannot
  shop as another.
- The catalog is the allowlist. A classname the client invents, or one asked
  for from a category it does not belong to, is rejected before delivery.
- Only attachments a weapon ships with in its own config are chargeable or
  installable, so arbitrary items cannot be smuggled in on a weapon line.
- Gear is applied on the shopper's own machine; the client refuses gear from
  any sender that is not the server.
- Vehicles appear at the base garage pad (`ITW_BASE_GARAGE_POS`), falling back
  to base centre where there is no pad, and are registered in
  `ITW_PlayerVehiclesList` so existing cleanup and persistence treat them
  normally.
- Ceilings per order: 120 lines, 50 per line, 4 vehicles.
- A checkout that gets no verdict within 20 seconds releases the Purchase
  button and says so, keeping the cart. Without that the button latches
  disabled for the rest of the session if a reply is ever lost, and the player
  has no way to recover but to close and reopen the store.

## Pricing

**The economy ships off.** With `ITW_CLASH_StoreEconomyEnabled = false` every
price reads 0, the cart never blocks, and all money is hidden: the store is
simply a better arsenal.

Nothing in the mission had a player currency to borrow from. The ticket pools
are HAL's. So rather than guess at an economy, the store exposes a flat,
auditable table to fill in. Edit `ITW_CLASH_Store.sqf`:

```sqf
ITW_CLASH_StoreEconomyEnabled = true;
ITW_CLASH_StoreStartingFunds set ["WEST", 25000];

ITW_CLASH_StoreCategoryPrices set ["primary", 120];   // whole category
ITW_CLASH_StorePrices set ["b_mbt_01_cannon_f", 4500]; // one class, wins
```

Resolution order per unit: free-list → exact classname → category fallback → 0.
Classname keys are lowercase; lookups are lowercased.

Prices are deliberately **not** derived from config mass or ballistics. FLO
does that in about 20 KB of heuristics; a table is auditable and it is the part
you asked to own.

## Saved loadouts

Whole `getUnitLoadout` arrays in the player's own Arma profile
(`ITW_CLASH_StoreLoadouts`), so they are per-computer and never cross the
network. Twenty per player, names capped at 40 characters, saving over a
duplicate name replaces it.

Loading is **priced and charged through the server exactly like a cart**, so
turning the economy on does not open a free-gear route. Only the loadout's
class list travels to the server; the loadout itself stays on the client and
only the verdict comes back. Classes the catalog no longer sells are charged
nothing and counted as unpriced rather than failing the request, so a loadout
saved before a pool changed is still wearable.

## Engine behaviour this design absorbs

`CT_WEBBROWSER` fails silently in several ways. Each of these is handled, and
each would otherwise present as "the menu is dead" rather than as an error.

| Behaviour | Handling |
|---|---|
| A page outside `allowedHTMLLoadURIs` renders but is **never given the `A3API` binding** | `class CfgCommands` in `description.ext` allowlists `ui\html\*`. The doubled backslashes are correct; do not "fix" them. |
| The `JSDialog` handler **must return a boolean** or the browser stays blocked | `ITW_CLASH_Store_fnc_HandleUiEvent` returns `true` on every path. |
| `ExecJS` before the page is up is **dropped, not queued** | Held in `ITW_CLASH_StoreBridge_Queues` and flushed on `PageLoaded` *or* on the page's first message, whichever wins the race. |
| `ExecJS` reads input as single-byte text, corrupting non-ASCII | `ITW_CLASH_Store_fnc_WebAction` escapes anything above 127 to `\uXXXX`. |
| page → SQF is **capped at 10240 characters and truncated silently** | The cart is sent as numbered chunks under a 6000-character budget, then committed. Inbound messages at the cap are rejected by name. An order whose chunks do not all arrive is refused, never part-filled. |
| `RequestTexture` fails by **resolving with a short stub**, not rejecting | Only a `data:`/`blob:`/`http(s):` result is accepted as an image; anything else falls back to a text badge. |
| `<script src>` cannot work: the page is a `blob:` URL with no base | Assets are pulled with `A3API.RequestFile` and injected inline. |
| `fetch`, `XMLHttpRequest`, `localStorage`, `IndexedDB` are blocked | All state round-trips through SQF; loadouts live in the Arma profile. |

### Known operational gotcha

**CSS animation only runs when Arma was launched through Steam.** Outside Steam
the browser is clamped to roughly 1 fps and every transition looks broken while
the rest of the game is fine. This is an engine-level frame-delivery clamp, not
a fault in the page. The store uses no animation, so the symptom here is only
sluggish hover and scroll feedback.

## Files

| File | Machine | Role |
|---|---|---|
| `ui/StoreDialog.hpp` | config | The dialog: one browser control, transparent, safe-zone sized |
| `ui/html/store.html` | client | Page skeleton and the asset boot stub |
| `ui/html/store.css` | client | Arsenal-style five-column layout |
| `ui/html/store.js` | client | Catalog rendering, cart, chunked checkout, preview input |
| `ITW_CLASH_Store.sqf` | all | Categories, **pricing table**, side wallets |
| `ITW_CLASH_StoreBridge.sqf` | all | `CT_WEBBROWSER` channel; reusable by another web interface |
| `ITW_CLASH_StoreCatalog.sqf` | server | Catalog from virtual cargo + `va_pAllVehicles`, cached per side |
| `ITW_CLASH_StoreServer.sqf` | server | Access validation, payloads, checkout, delivery |
| `ITW_CLASH_StoreClient.sqf` | client | Dialog, event routing, gear application, loadouts, preview scene |

Loaded from `preInit.sqf` (config, catalog, server, bridge) and
`initPlayerLocal.sqf` (client).

## Integration seams

Three places to change if the defaults are wrong for your campaign:

1. **Prices**: `ITW_CLASH_Store.sqf`, as above.
2. **Vehicle delivery**: `ITW_CLASH_Store_fnc_SpawnVehicle`. Currently
   `createVehicle` at the garage pad. Replace this one function to route
   purchases through `ITW_Garage` instead.
3. **Who may shop**: `ITW_CLASH_Store_fnc_ValidateAccess`. Add a rank, role or
   objective-ownership test here; it is the single chokepoint every request
   passes through.

Call `ITW_CLASH_Store_fnc_InvalidateCatalog` on the server if the mission ever
changes the arsenal or vehicle pools mid-session; the catalog is cached per
side on first use.

## Not included

- No algorithmic pricing (deliberate; see above).
- No AI recruiting or supply-shipment entries. FLO's versions of these are tied
  to its force generation and logistics network, neither of which exists here.
- No supply-throughput gating. FLO locks items a base's logistics node cannot
  fulfil; Clash has no equivalent per-base node, so nothing is locked. The
  `locked` / `lockReason` fields are carried through the payload and honoured by
  the interface, so a future gate needs no interface work.
