# UI screenshots

Applies to: `profile/images/*.png`, which are used by the step-5 walkthrough in
[profile/README.md](../../profile/README.md). Regenerate them whenever the UI changes the screens
they show.

The script drives the real UI against a local throwaway stack, using headless Microsoft Edge
through `playwright-core` (no browser download). Run everything outside the repositories, so that
no runtime data lands in a working tree.

## Safety first

- **Publish the Node in Release.** Debug builds load `Data/local.configuration.json` and ignore
  MQTT configuration. With a developer's local file present, a Debug build starts real devices
  with real credentials.
- **Delete local data from the publish output** before starting anything. The Web SDK publishes
  every `**/*.json`, so the output contains copies of local, gitignored data:
  - Orchestrator: `StoredObjects/`
  - Node: `Data/`
- **Use the bundled broker.** It listens on `127.0.0.2:1883`, so it can't mix with a Mosquitto
  already running on `127.0.0.1:1883`. Set `RIOT2_MQTT_IP=127.0.0.2`.

## Steps (PowerShell, from `C:\Src\RIoT2`)

1. Publish to a temporary folder, remove local data, and add the default plugins:

   ```powershell
   $s = "$env:TEMP\riot2-shots"
   dotnet publish .\RIoT2.Net.Orchestrator\RIoT2.Net.Orchestrator.csproj -c Release -o "$s\orchestrator"
   dotnet publish .\RIoT2.Net.Node\RIoT2.Net.Node.csproj -c Release -o "$s\node"
   dotnet publish .\RIoT2.Net.Devices\RIoT2.Net.Devices.csproj -c Release -o "$s\devices"
   Remove-Item -Recurse -Force "$s\orchestrator\StoredObjects", "$s\node\Data" -ErrorAction SilentlyContinue
   New-Item -ItemType Directory -Force "$s\node\Plugins" | Out-Null
   $have = Get-ChildItem "$s\node" -File | ForEach-Object Name
   Get-ChildItem "$s\devices" -Filter *.dll | Where-Object { $have -notcontains $_.Name } | Copy-Item -Destination "$s\node\Plugins"
   ```

2. Start each process in its own terminal:

   ```powershell
   # broker (in .github\tools\ui-screenshots)
   npm install; npm run broker
   # orchestrator (in $s\orchestrator)
   $env:RIOT2_ORCHESTRATOR_ID='0F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9'; $env:RIOT2_ORCHESTRATOR_URL='http://localhost:8080'; $env:RIOT2_MQTT_IP='127.0.0.2'; $env:ASPNETCORE_URLS='http://localhost:8080'; dotnet .\RIoT2.Net.Orchestrator.dll
   # node (in $s\node)
   $env:RIOT2_NODE_ID='5A1E7C3B-2D4F-4E6A-9B8C-7D6E5F4A3B21'; $env:RIOT2_NODE_URL='http://localhost:8081'; $env:RIOT2_MQTT_IP='127.0.0.2'; $env:ASPNETCORE_URLS='http://localhost:8081'; dotnet .\RIoT2.Net.Node.dll
   # UI (in RIoT2.UI; .env already points MQTT at localhost)
   npx vite --port 5173 --strictPort
   ```

3. Capture the screenshots. The orchestrator must start with an empty store, because the script
   creates "Garage node":

   ```powershell
   npm run capture
   ```

4. Look at every image before committing it. Then stop all processes and delete `$s`.

## Notes

- The UI announces itself only once, when the page loads. If the broker restarts, reload the
  page.
- The screenshots show the UI exactly as it is, including the "Rules" menu label for the Elsa
  link and the "Varibles" typo. Fix those in RIoT2.UI, not in the images.
