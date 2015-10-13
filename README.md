# Desktopfile

D library for working with *.desktop* files. Desktop entries in Freedesktop world are akin to shortcuts from Windows world (.lnk files).

[![Build Status](https://travis-ci.org/MyLittleRobo/desktopfile.svg?branch=master)](https://travis-ci.org/MyLittleRobo/desktopfile) [![Coverage Status](https://coveralls.io/repos/MyLittleRobo/desktopfile/badge.svg?branch=master&service=github)](https://coveralls.io/github/MyLittleRobo/desktopfile?branch=master)

The most of desktop environments on Linux and BSD flavors follows [Desktop Entry Specification](http://standards.freedesktop.org/desktop-entry-spec/latest/) today.
The goal of **desktopfile** library is to provide implementation of this specification in D programming language.
Please feel free to propose enchancements or report any related bugs to *Issues* page.

## Platform support

The library is crossplatform for the most part, though there's little sense to use it on systems that don't follow freedesktop specifications.
**desktopfile** is developed and tested on FreeBSD and Debian GNU/Linux.

## Generating documentation

Ddoc:

    dub build --build=docs
    
Ddox:

    dub build --build=ddox

## Running tests

    dub test
    
## Examples

### Desktop util

Utility that can parse, execute and rewrites .desktop files.
This will start vlc with the first parameter set to $HOME/Music:

    dub run desktopfile:desktoputil -- exec /usr/share/applications/vlc.desktop $HOME/Music
    
This should start command line application in terminal emulator (will be detected automatically):

    dub run desktopfile:desktoputil -- exec /usr/share/applications/python2.7.desktop
    
Run in specific terminal emulator:

    dub run desktopfile:desktoputil -- exec /usr/share/applications/python2.7.desktop --term=xterm

Additional application actions are supported too:

    dub run desktopfile:desktoputil -- exec /usr/share/applications/steam.desktop --action=Settings
    
Open link with preferred application:

    dub run desktopfile:desktoputil -- link /usr/share/desktop-base/debian-homepage.desktop

Starts .desktop file defined executable or opens link:

    dub run desktopfile:desktoputil -- start /path/to/file.desktop
    
Parse and write .desktop file to new location (to testing purposes):

    dub run desktopfile:desktoputil -- write /usr/share/applications/vlc.desktop $HOME/Desktop/vlc.desktop

Read basic information about desktop file:

    dub run desktopfile:desktoputil -- read /usr/share/applications/kde4/kate.desktop
 
### Desktop test

Parses all .desktop files in system's applications paths (usually /usr/local/share/applicatons and /usr/share/applications) and on the user's Desktop.
Writes errors (if any) to stderr.
Use this example to check if the desktopfile library can parse all .desktop files on your system.

    dub run desktopfile:desktoptest --build=release

To print all directories examined by desktoptest to stdout, build it in non-release mode:

    dub run desktopfile:desktoptest

Start desktoptest on specified directories:

    dub run desktopfile:desktoptest -- /path/to/applications /anotherpath/to/applications
    # Example using cmd on Windows (KDE installed):
    dub run desktopfile:desktoptest -- "%SYSTEMDRIVE%\ProgramData\KDE\share\applications" "%APPDATA%\.kde\share"
    
    