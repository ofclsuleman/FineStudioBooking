## FINE STUDIO BOOKING MANAGEMENT
================================

## ABOUT
Fine Studio Booking Management is a Windows desktop booking-management app built with PowerShell and Windows Presentation Foundation (WPF).

## PROJECT CONTENTS
- FineStudioBooking.ps1     Main application script
- Run Fine Studio.bat       Recommended launcher (starts PowerShell in STA mode)
- README.txt                Setup and usage notes
- LICENSE.txt               Project usage and redistribution terms
- CHANGELOG.md              Summary of this packaged build
- SUPPORT.txt               Troubleshooting and support notes
- .gitignore                Suggested exclusions for version control
- data\                    Local application data folder

## REQUIREMENTS
- Windows 10 or Windows 11
- Windows PowerShell 5.1
- Windows desktop/WPF components available on the PC
- No separately installed PowerShell modules are expected to be required

## START THE APP
1. Extract the complete FineStudioBooking_Project folder to a normal, writable location, such as Documents.
2. Keep the script, launcher, and data folder together.
3. Double-click "Run Fine Studio.bat".
4. If Windows displays a security prompt, verify that you trust the source before allowing it to run.

## ALTERNATIVE STARTUP
Open Windows PowerShell in this folder and run:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File ".\FineStudioBooking.ps1"

## DATA AND BACKUPS
- The application stores local data in the data folder. JSON files may be created there when the app is used.
- Keep the data folder in the same project folder so the app can find its data.
- Back up the entire data folder regularly, especially before replacing the application script.
- Treat the data folder as private: it may contain booking and account information. Do not upload or share it publicly.
- Do not delete or replace data files unless you have a backup and understand the consequences.

## OPTIONAL LOGO
An optional file named logo.png can be placed beside FineStudioBooking.ps1 if the application supports and detects it in this build.

## TROUBLESHOOTING
- If the app does not open, run it using the BAT launcher so any PowerShell error remains visible.
- If an error appears, copy the complete error text, including the line number, and keep a copy of the exact FineStudioBooking.ps1 file you ran.
- If the app behaves unexpectedly after an update, close it, back up data, and confirm you are running the script from the newly extracted folder rather than an older copy.
- Do not assume a build is fully runtime-tested just because it opens or its XAML parses. Verify booking creation, editing, saving, theme switching, and dialogs on the target PC.

## LIMITATIONS
This package was prepared in a non-Windows environment. The application has not been executed here on Windows, so compatibility and runtime behavior should be checked on the target machine.

## VERSIONING
See CHANGELOG.md for notes about this packaged build. No formal semantic version has been assigned.
