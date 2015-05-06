# Desktopfile

D library for working with .desktop files. See [Desktop Entry Specification](http://standards.freedesktop.org/desktop-entry-spec/latest/).

## Generating documentation

Ddoc:

    dub build --build=docs
    
Ddox:

    dub build --build=ddox

## Running tests

    dub test
    
## Examples

See examples/ directory.

### Desktop util

Utility that can parse and execute .desktop files.
This will start vlc with the first parameter set to ~/Music:

    dub run desktopfile:desktoputil -- exec /usr/share/applications/vlc.desktop ~/Music
    
Starting the command line application should start it in terminal emulator:

    dub run desktopfile:desktoputil -- exec /usr/share/applications/python2.7.desktop
    
Parse and write .desktop file to new location:

    dub run desktopfile:desktoputil -- write /usr/share/applications/vlc.desktop ~/Desktop/vlc.desktop

### Desktop test

Parses all .desktop files in system's applications paths (usually /usr/local/share/applicatons and /usr/share/applications).
Writes errors (if any) to stderr.
Use this example to check if the desktopfile library can parse all .desktop files on your system.

    dub run desktopfile:desktoptest --build=release



