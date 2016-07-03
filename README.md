# Desktopfile

D library for working with *.desktop* files. Desktop entries in Freedesktop world are akin to shortcuts from Windows world (.lnk files).

[![Build Status](https://travis-ci.org/MyLittleRobo/desktopfile.svg?branch=master)](https://travis-ci.org/MyLittleRobo/desktopfile) [![Coverage Status](https://coveralls.io/repos/MyLittleRobo/desktopfile/badge.svg?branch=master&service=github)](https://coveralls.io/github/MyLittleRobo/desktopfile?branch=master)

[Online documentation](https://mylittlerobo.github.io/d-freedesktop/docs/desktopfile.html)

Most desktop environments on GNU/Linux and BSD flavors follow [Desktop Entry Specification](https://www.freedesktop.org/wiki/Specifications/desktop-entry-spec/) today.
The goal of **desktopfile** library is to provide implementation of this specification in D programming language.
Please feel free to propose enchancements or report any related bugs to *Issues* page.

## Platform support

The library is crossplatform for the most part, though there's little sense to use it on systems that don't follow freedesktop specifications.
**desktopfile** is developed and tested on FreeBSD and Debian GNU/Linux.

## Features

### Implemented features

**desktopfile** provides basic features like reading and executing desktop files, and more:

* [Exec](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s06.html) value unquoting and unescaping. Expanding field codes.
* Starting several instances of application if it supports only %f or %u and not %F or %U.
* Can rewrite desktop files preserving all comments and the original order of groups [as required by spec](https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s02.html).
* Retrieving [Desktop file ID](http://standards.freedesktop.org/desktop-entry-spec/latest/ape.html).
* Support for [Additional application actions](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s10.html).
* Determining default terminal command to run applications with Terminal=true. Note that default terminal detector may not work properly on particular system since there's no standard way to find default terminal emulator that would work on every distribution and desktop environment. If you strive for better terminal emulator detection you may look at [xdg-terminal.sh](https://src.chromium.org/svn/trunk/deps/third_party/xdg-utils/scripts/xdg-terminal).

### Missing features

Features that currently should be handled by user, but may be implemented in the future versions of library.

* [D-Bus Activation](http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s07.html).
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

### [Desktop util](examples/util/source/app.d)

Utility that can parse, execute and rewrites .desktop files.

This will open $HOME/.bashrc in geany text editor:

    dub run :util -- exec /usr/share/applications/geany.desktop dub.json
    
This should start command line application in terminal emulator (will be detected automatically):

    dub run :util -- exec /usr/share/applications/python2.7.desktop

Additional application actions are supported too:

    dub run :util -- exec /usr/share/applications/steam.desktop --action=Settings
    
Running of multiple application instances if it does not support handling multiple urls:

    dub run :util -- exec /usr/share/applications/leafpad.desktop dub.json README.md
    
Open link with preferred application:

    dub run :util -- open /usr/share/desktop-base/debian-homepage.desktop

Starts .desktop file defined executable or opens link:

    dub run :util -- start /path/to/file.desktop
    
Parse and write .desktop file to new location (for testing purposes):

    dub run :util -- write /usr/share/applications/vlc.desktop $HOME/Desktop/vlc.desktop

Read basic information about desktop file:

    dub run :util -- read /usr/share/applications/kde4/kate.desktop
    
When passing base name of desktop file instead of path it's treated like desktop file id and desktop file is searched in system applications paths.

    dub run :util -- exec python2.7.desktop
    dub run :util -- exec kde4-kate.desktop

On non-freedesktop systems appPath should be passed and PATH variable prepared. Example using cmd on Windows (KDE installed):

    set PATH=C:\ProgramData\KDE\bin
    dub run :util -- --appPath=C:\ProgramData\KDE\share\applications exec kde4-gwenview.desktop

Executing .desktop files with complicated Exec lines:

    dub run :util -- exec "$HOME/.local/share/applications/wine/Programs/True Remembrance/True Remembrance.desktop" # launcher that was generated by wine
    dub run :util -- exec $HOME/TorBrowser/tor-browser_en-US/start-tor-browser.desktop # Tor browser launcher
    
### [Desktop test](examples/test/source/app.d)

Parses all .desktop files in system's applications paths (usually /usr/local/share/applicatons and /usr/share/applications) and on the user's Desktop.
Writes errors (if any) to stderr.
Use this example to check if the desktopfile library can parse all .desktop files on your system.

    dub run :test

To print all directories examined by desktoptest to stdout, add --verbose flag:

    dub run :test -- --verbose

Start desktoptest on specified directories:

    dub run :test -- /path/to/applications /anotherpath/to/applications
    
Example using cmd on Windows (KDE installed):

    set KDE_SHARE="%SYSTEMDRIVE%\ProgramData\KDE\share"
    dub run :test -- %KDE_SHARE%\applications %KDE_SHARE%\templates %KDE_SHARE%\desktop-directories %KDE_SHARE%\autostart
    
### [Shoot desktop file](examples/shoot/source/app.d)

Uses the alternative way of starting desktop file. Instead of constructing DesktopFile object it just starts the application or opens link after read enough information from file.

    dub run :shoot -- vlc.desktop
    dub run :shoot -- python2.7.desktop
    dub run :shoot -- geany.desktop dub.json
    
Running of multiple application instances if it does not support handling multiple urls:

    dub run :shoot -- leafpad.desktop dub.json README.md

On Windows (KDE installed):

    set PATH=C:\ProgramData\KDE\bin;%PATH%
    dub run :shoot -- C:\ProgramData\KDE\share\applications\kde4\gwenview.desktop
