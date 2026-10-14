# Save and Continue

Quitting while alive saves the world (terrain edits, inventory, player position and health). The main menu then offers Continue, which restores that snapshot. Dying drops the Continue file; with no snapshot Continue is disabled.

## Sub-features

- `save-alive-quit` alive quit writes the continue file.
- `continue-restore` menu Continue loads the snapshot back.
- `continue-dead` dead quit removes it.
- `continue-disabled` no snapshot means Continue is disabled.
- `frontend-catalog` world create/load/incomplete-bake rows and return-to-select.

## How to get to it (user POV)

- Quit to menu while alive; on the frontend press Continue. `quick_save`/`quick_load` in world.

## Driving it with cs-verify.sh

Preconditions:

- `doctor` OK, `quick` OK. Saves land under `APPDATA=D:\csmerge\appdata` (wrapper), never Cole's profile.

- **Save round trip.** Run `bash $S feature save-continue`. `OK world save/load overlays + player`, `OK continue file after alive quit`.
- **Continue.** Same run: `OK menu Continue arms the alive snapshot`, `OK continue load restores the alive snapshot`.
- **Negative paths.** `OK dead quit drops continue`, `OK Continue disabled without a snapshot`, `OK return_to_select clears resume flags`.
- **World catalog.** Run `bash $S feature frontend`. Marker `All world frontend flow tests OK`.
- **Proof.** Logs `feature-save-continue.log`, `feature-frontend.log`.

## Gotchas

- Suites use a stub player and world id `verify_resume_tmp`; the visible menu button is unverified headless.
- Both are abrupt-exit suites: 137/134 after the marker is a pass.
