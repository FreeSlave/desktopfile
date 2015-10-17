# Desktopfile

D library for working with *.desktop* files. Desktop entries in Freedesktop world are akin to shortcuts from Windows world (.lnk files).

[![Build Status](https://travis-ci.org/MyLittleRobo/desktopfile.svg?branch=master)](https://travis-ci.org/MyLittleRobo/desktopfile) [![Coverage Status](https://coveralls.io/repos/MyLittleRobo/desktopfile/badge.svg?branch=master&service=github)](https://coveralls.io/github/MyLittleRobo/desktopfile?branch=master)

The most of desktop environments on Linux and BSD flavors follows [Desktop Entry Specification](http://standards.freedesktop.org/desktop-entry-spec/latest/) today.
The goal of **desktopfile** library is to provide implementation of this specification in D programming language.
Please feel free to propose enchancements or report any related bugs to *Issues* page.

## Platform support

The library is crossplatform for the most part, though there's little sense to use it on systems that don't follow freedesktop specifications.
**desktopfile** is developed and tested on FreeBSD and Debian GNU/Linux.

## Features

### Implemented features

**desktopfile** provides basic features like reading and running desktop files, and more:

* [Exec](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s06.html) value unquoting and unescaping. Expanding field codes.
* Can rewrite desktop files preserving all comments and the original order of groups.
* Retrieving [Desktop file ID](http://standards.freedesktop.org/desktop-entry-spec/latest/ape.html).
* Support for [Additional application actions](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s10.html).
* Determining default terminal command to run applications with Terminal=true.

### Missing features

Features that currently should be handled by user, but may be implemented in the future versions of library.

* [D-Bus Activation](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s07.html).
* Startup Notification Protocol.
* Copying files to local file system when %f field code is used.
* Starting several instances of application if it supports only %f and not %F.

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

To print all directories examined by desktoptest to stdout, add --verbose flag:

    dub run desktopfile:desktoptest -- --verbose

Start desktoptest on specified directories:

    dub run desktopfile:desktoptest -- /path/to/applications /anotherpath/to/applications
    
Example using cmd on Windows (KDE installed):

    set KDE_SHARE="%SYSTEMDRIVE%\ProgramData\KDE\share"
    dub run desktopfile:desktoptest -- %KDE_SHARE%\applications %KDE_SHARE%\templates %KDE_SHARE%\desktop-directories %KDE_SHARE%\autostart
    
    