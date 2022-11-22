# Lomiri (formely Unity 8) on Void Linux
[Lomiri](https://lomiri.com/) is the desktop (or rather mobile) environment used by [Ubuntu Touch](https://ubuntu-touch.io/).

## Screenshot
![]()

## Finding files in built packages
```sh
lgrep() { for p in hostdir/binpkgs/lomiri/*.x86_64.xbps; do tar tvf $p | grep "$1" && echo "^^^ $(basename $p) ^^^"; done; }

# example
lgrep TerminalWindow
-rw-r--r-- 0/0            6014 2022-11-22 18:31 ./usr/share/lomiri-terminal-app/qml/TerminalWindow.qml
^^^ lomiri-terminal-app-1.0.3r905_1.x86_64.xbps ^^^
```

## Checking all relevant package updates
```sh
for p in qmltermwidget $(gl --oneline origin/master..HEAD | grep -Po 'New package: \K.*(?=-[0-9])'); do ./xbps-src update-check $p; done
```

## Reduce log spam (until UT is on Qt 5.15 and QML syntax can be edited)
```sh
export QT_LOGGING_RULES="qt.qml.connections=false"
```
* Reference: https://github.com/qt/qtdeclarative/commit/a2eef6b

## For editing QML after installation
```sh
export QML_DISABLE_DISK_CACHE=1
```

## Original README.md
[README.voidlinux.md](README.voidlinux.md)
