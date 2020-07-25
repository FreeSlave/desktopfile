# Desktopfile

D library for working with *.desktop* files. Desktop entries in Freedesktop world are akin to shortcuts from Windows world (.lnk files).

[![Build Status](https://travis-ci.org/FreeSlave/desktopfile.svg?branch=master)](https://travis-ci.org/FreeSlave/desktopfile) [![Coverage Status](https://coveralls.io/repos/FreeSlave/desktopfile/badge.svg?branch=master&service=github)](https://coveralls.io/github/FreeSlave/desktopfile?branch=master)

[Online documentation](https://freeslave.github.io/d-freedesktop/docs/desktopfile.html)

Most desktop environments on GNU/Linux and BSD flavors follow [Desktop Entry Specification](https://www.freedesktop.org/wiki/Specifications/desktop-entry-spec/) today.
The goal of **desktopfile** library is to provide implementation of this specification in D programming language.
Please feel free to propose enchancements or report any related bugs to *Issues* page.

## Platform support

The library is crossplatform for the most part, though there's little sense to use it on systems that don't follow freedesktop specifications.
**desktopfile** is developed and tested on FreeBSD and Debian GNU/Linux.

## Features

### Implemented features

**desktopfile** provides basic features like reading and executing desktop files, and more:

* [Exec](https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s07.html) value unquoting and unescaping. Expanding field codes.
* Starting several instances of application if it supports only %f or %u and not %F or %U.
* Can rewrite desktop files preserving all comments and the original order of groups [as required by spec](https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s03.html).
* Retrieving [Desktop file ID](https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s02.html#desktop-file-id).
* Support for [Additional application actions](https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s11.html).
* Determining default terminal command to run applications with Terminal=true. Note that default terminal detector may not work properly on particular system since there's no standard way to find default terminal emulator that would work on every distribution and desktop environment. If you strive for better terminal emulator detection you may look at [xdg-terminal.sh](https://src.chromium.org/svn/trunk/deps/third_party/xdg-utils/scripts/xdg-terminal).

### Missing features

Features that currently should be handled by user, but may be implemented in the future versions of library.

* [D-Bus Activation](https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s08.html).
* Startup Notification Protocol.
* Copying files to local file system when %f or %F field code is used.
* Support for Ayatana Desktop Shortcuts used in Unity. This is not part of Desktop Entry and actually violates the specification.

## Brief

```d
import std.stdio;
import std.array;
import std.process;

import desktopfile;

string filePath = ...;
string[] urls = ...;

try {
    auto df = new DesktopFile(filePath);

    //Detect current locale.
    string locale = environment.get("LC_CTYPE", environment.get("LC_ALL", environment.get("LANG")));

    string name = df.localizedDisplayName(locale); //Specific name of the application.
    string genericName = df.localizedGenericName(locale); //Generic name of the application. Show it in menu under the specific name.
    string comment = df.localizedComment(locale); //Show it as tooltip or description.

    string iconName = df.iconName(); //Freedesktop icon name.

    if (df.hidden()) {
        //User uninstalled desktop file and it should not be shown in menus.
    }

    string[] onlyShowIn = df.onlyShowIn().array; //If not empty, show this application only in listed desktop environments.
    string[] notShowIn = df.notShowIn().array; //Don't show this application in listed desktop environments.

    string[] mimeTypes = df.mimeTypes().array; //MIME types supported by application.
    string[] categories = df.categories().array; //Menu entries where this application should be shown.
    string[] keywords = df.keywords().array; //Keywords can be used to improve searching of the application.

    foreach(action; df.byAction()) { //Supported actions.
        string actionName = action.localizedDisplayName(locale);
        action.start(locale);
    }

    if (df.type() == DesktopFile.Type.Application) {
        //This is application
        string commandLine = df.execValue(); //Command line pattern used to start the application.
        try {
            df.startApplication(urls, locale); //Start application using given arguments and specified locale. It will be automatically started in terminal emulator if required.
        }
        catch(ProcessException e) { //Failed to start the application.
            stderr.writeln(e.msg);
        }
        catch(DesktopExecException e) { //Malformed command line pattern.
            stderr.writeln(e.msg);
        }
    } else if (df.type() == DesktopFile.Type.Link) {
        //This is link to file or web resource.
        string url = df.url(); //URL to open

    } else if (df.type() == DesktopFile.Type.Directory) {
        //This is directory or menu section description.
    } else {
        //Type is not defined or unknown, e.g. KDE Service.
        string type = df.value("Type"); //Retrieve value manually as string if you know how to deal with non-standard types.
    }
}
catch (IniLikeException e) { //Parsing error - file is not desktop file or has errors.
    stderr.writeln(e.msg);
}

```

## Examples

### [Desktop util](examples/util.d)

Utility that can parse, execute and rewrite .desktop files.

This will open dub.json in geany text editor:

    dub examples/util.d exec /usr/share/applications/geany.desktop dub.json

This should start command line application in terminal emulator (will be detected automatically):

    dub examples/util.d exec /usr/share/applications/python2.7.desktop

Additional application actions are supported too:

    dub examples/util.d exec /usr/share/applications/steam.desktop --action=Settings
    dub examples/util.d exec /usr/share/applications/qpdfview.desktop --action NonUniqueInstance /path/to/pdf/file

Running of multiple application instances if it does not support handling multiple urls:

    dub examples/util.d exec /usr/share/applications/leafpad.desktop dub.json README.md

Open a link with preferred application:

    dub examples/util.d open /usr/share/desktop-base/debian-homepage.desktop

Look up the .desktop file type and executes it if it's an application or opens a link if it's a link.

    dub examples/util.d start /path/to/file.desktop

Parse and write .desktop file to new location (for testing purposes):

    dub examples/util.d write /usr/share/applications/vlc.desktop $HOME/Desktop/vlc.desktop

Read basic information about desktop file:

    dub examples/util.d read /usr/share/applications/kde4/kate.desktop

When passing base name of desktop file instead of path it's treated as a desktop file id and desktop file is searched in system applications paths.

    dub examples/util.d exec python2.7.desktop
    dub examples/util.d exec kde4-kate.desktop

On non-freedesktop systems appPath should be passed and PATH variable prepared. Example using cmd on Windows (KDE installed):

    set PATH=C:\ProgramData\KDE\bin
    dub examples/util.d --appPath=C:\ProgramData\KDE\share\applications exec kde4-gwenview.desktop

Executing .desktop files with complicated Exec lines:

    dub examples/util.d exec "$HOME/.local/share/applications/wine/Programs/True Remembrance/True Remembrance.desktop" # launcher that was generated by wine
    dub examples/util.d exec $HOME/TorBrowser/tor-browser_en-US/start-tor-browser.desktop # Tor browser launcher

### [Desktop test](examples/test.d)

Parses all .desktop files in system's applications paths (usually /usr/local/share/applicatons and /usr/share/applications) and on the user's Desktop.
Writes errors (if any) to stderr.
Use this example to check if the desktopfile library can parse all .desktop files on your system.

    dub examples/test.d

To print all directories examined by desktoptest to stdout, add --verbose flag:

    dub examples/test.d --verbose

Start desktoptest on specified directories:

    dub examples/test.d -- /path/to/applications /anotherpath/to/applications

Example using cmd on Windows (KDE installed):

    set KDE_SHARE="%SYSTEMDRIVE%\ProgramData\KDE\share"
    dub examples/test.d -- %KDE_SHARE%\applications %KDE_SHARE%\templates %KDE_SHARE%\desktop-directories %KDE_SHARE%\autostart

### [Fire desktop file](examples/fire.d)

Uses the alternative way of starting desktop file. Instead of constructing DesktopFile object it just starts a referenced application or opens a link after it read enough information from file.

    dub examples/fire.d vlc.desktop
    dub examples/fire.d python2.7.desktop
    dub examples/fire.d geany.desktop dub.json

Running multiple application instances if it does not support handling multiple urls:

    dub examples/fire.d leafpad.desktop dub.json README.md

On Windows (KDE installed):

    set PATH=C:\ProgramData\KDE\bin;%PATH%
    dub examples/fire.d C:\ProgramData\KDE\share\applications\kde4\gwenview.desktop
