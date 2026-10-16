# Cogent Automation Label Printer (Local Web App)

A Windows-friendly local web application for uploading one or many PDF drawings, uploading a company logo, generating QR labels at **50 × 30 mm**, printing selected labels, downloading combined label PDFs, and keeping print history.

## Start the application on your Windows PC

1. Download and extract the ZIP file to a folder such as `C:\CogentLabelPrinter`.
2. Double-click **`start.bat`**.
3. Your browser should open **http://localhost:3000**. If it does not, open that address manually.
4. Keep the black PowerShell window open while you use the application. Closing it stops the local server.
5. An internet connection is needed because the PDF and QR-code libraries load from CDN URLs the first time the app is used.

No Node.js installation is needed. The app uses Windows PowerShell and the built-in HTTP listener.

## Main workflow

1. Click **Upload PDF Files** and select one or multiple PDF drawings.
2. Click **Upload Company Logo** and choose your logo image (PNG, JPG, or SVG).
3. Review or edit the part number and drawing number for each drawing.
4. Select the labels to print and set the quantity for each row.
5. Click **Print Selected Labels** or **Download Combined PDF**.
6. In the printer dialog, choose the label printer and set the paper size to **50 × 30 mm**, scale to **100% / Actual size**, and margins to **None**.

The combined PDF has one 50 × 30 mm page per label. You can use it to print later or as a fallback if your printer driver does not accept direct browser printing.

## Scanning QR codes from a phone

The server creates a unique link for each saved drawing. For a phone to open it:

- The PC and phone should be on the same trusted Wi-Fi/network.
- The app must be running on the PC.
- Windows Firewall may ask permission; allow access only on your trusted private network.
- The URL used in the QR code must be reachable from the phone. Open **Settings → QR Base URL** to view or edit it. Use the PC's LAN IPv4 address, for example `http://192.168.1.25:3000` (use your real PC address, not this example).

### If QR codes only open on the PC

The first start may fall back to localhost-only mode if Windows has not reserved the listener URL. To enable local-network access, open **PowerShell as Administrator** once and run:

```powershell
netsh http add urlacl url=http://+:3000/ user=Everyone
```

Then close and restart `start.bat`. If the Windows Firewall prompt appears, permit access on your trusted private network. Confirm the QR Base URL points to the correct PC LAN IP address.

**Important:** `localhost` inside a QR code means the device scanning it, not your PC. Do not use `http://localhost:3000` as the QR Base URL for phone scanning. Use the PC's LAN address. For access outside your local network, deploy the app to a secured server and set the QR Base URL to its HTTPS address.

## Data and privacy

The app stores PDF drawings, metadata, and print history in a `data` folder beside `server.ps1`; back up that folder. The logo and user settings are stored in the browser's local storage on that PC/browser. QR links use long random tokens, but anyone who has a drawing's link can open that PDF. Use only on a trusted network and do not expose this HTTP server directly to the public internet.

## Troubleshooting

- **Page does not load:** keep the PowerShell window open; try `http://localhost:3000`; check whether another application already uses port 3000.
- **Phone cannot open a drawing:** check same Wi-Fi, Windows Firewall, URL reservation, and the QR Base URL setting.
- **QR/PDF buttons report missing libraries:** connect to the internet and refresh the page.
- **Label size is wrong:** configure the printer driver for 50 × 30 mm and print at 100% / Actual size with no margins. Some printers require creating a custom label stock size in the printer preferences first.
