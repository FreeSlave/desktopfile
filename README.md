# Desktopfile

D library for working with .desktop files. See [Desktop Entry Specification](http://standards.freedesktop.org/desktop-entry-spec/latest/).

## Generating documentation

    dub build --build=docs

## Running tests

    dub test
    
## Examples

### Desktop util

Utility that can parse and execute .desktop files.
Start vlc:

    dub run desktopfile:desktoputil -- exec /usr/share/applications/vlc.desktop ~/Music
    
Parse and write .desktop file to new location:

    dub run desktopfile:desktoputil -- write /usr/share/applications/vlc.desktop ~/Desktop/vlc.desktop

