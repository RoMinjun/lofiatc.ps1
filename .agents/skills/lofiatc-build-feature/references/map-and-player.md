# Map and player features

## Interactive map

- Keep browser state and PowerShell session state synchronized during initial selection and repeated changes.
- Treat action names, ICAOs, channel indexes, URLs, and volumes received from the browser as untrusted.
- Reuse existing escaping and JSON serialization patterns for generated HTML and JavaScript.
- Preserve `-NoWeather`, persistent mode, favorites, random selection, webcam, lofi, and channel switching.
- Avoid blocking the request loop with unrelated work.
- Clean up listeners, temporary files, and managed processes after success, error, timeout, or cancellation.
- Test the initial state and actions after playback has already started.

## Players and media processes

- Keep URL resolution separate from process launch.
- Isolate VLC, MPV, PotPlayer, and MPC-HC arguments; never assume flag parity.
- Preserve audio-only and video behavior for ATC, lofi, and webcams.
- Stop or replace managed processes deliberately and test that repeat actions do not orphan processes.
- Keep optional programs optional unless the selected feature genuinely requires them.
- Mock command discovery and process creation in tests.
