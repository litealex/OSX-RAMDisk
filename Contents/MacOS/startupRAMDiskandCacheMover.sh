#!/usr/bin/env bash -x

# Copyright Zafar Khaydarov
#
# This is about to create a RAM disk in OS X and move the apps caches into it
# to increase performance of those apps.
# Performance gain is very significant, particularly for browsers and
# especially for IDEs like IntelliJ Idea
#
# Drawbacks and risks are that if RAM disk becomes full - performance will degrate
# significantly.
#
# USE AT YOUR OWN RISK. PLEASE NOTE IT WILL NOT CHECK FOR CORRUPTED FILES
# IF YOUR RAM IS BROKEN - DO NOT USE IT.
#

# The RAM amount you want to allocate for RAM disk. One of
# 1024 2048 3072 4096 5120 6144 7168 8192
# By default will use 1/4 of your RAM

ramfs_size_mb=$(sysctl hw.memsize | awk '{print $2;}')
ramfs_size_mb=$((${ramfs_size_mb} / 1024 / 1024 / 4))

mount_point=/Volumes/ramdisk
ramfs_size_sectors=$((${ramfs_size_mb}*1024*1024/512))
ramdisk_device=`hdid -nomount ram://${ramfs_size_sectors}`
USERRAMDISK="$mount_point/${USER}"


# Checks user response.
user_response()
{
    read -p " ${1} [y/n]" ${response}
    case ${response} in
        [yY][eE][sS]|[yY]|"")
            true
            ;;
        [nN][oO]|[nN])
            false
            ;;
        *)
            user_response ${@}
            ;;
    esac
}

#
# Closes passed as arg app by name
#
close_app()
{
    osascript -e "quit app \"${1}\""
}

#
# Creates RAM Disk.
#
mk_ram_disk()
{
    # unmount if exists the RAM disk and mounts if doesn't
    umount -f ${mount_point}
    newfs_hfs -v 'ramdisk' ${ramdisk_device}
    mkdir -p ${mount_point}
    mount -o noatime -t hfs ${ramdisk_device} ${mount_point}

    echo "created RAM disk."
    # Hide RAM disk - we don't really need it to be annoiyng in finder.
    # comment out should you need it.
    hide_ramdisk
    echo "RAM disk hidden"
}

# adds rsync to be executed each 5 min for current user
add_rsync_to_cron()
{
    #todo fixme
    crontab -l | { cat; echo "5 * * * * rsync"; } | crontab -
}

# Open an application
open_app()
{
    osascript -e "tell app \"${1}\" to activate"
}

# Hide RamDisk directory
hide_ramdisk()
{
    /usr/bin/chflags hidden ${mount_point}
}

# Checks that we have
# all required utils before proceeding
check_requirements()
{
    hash rsync 2>/dev/null || { echo >&2 "No rsync has been found.  Aborting. If you use brew install using: 'brew install rsync'"; exit 1; }
    hash newfs_hfs 2>/dev/null || { echo >&2 "No newfs_hfs has been found.  Aborting."; exit 1; }
}

#
# Check existnce of the string in file.
#
check_string_in_file()
{
    if  grep "${1}" "${2}" == 0; then
        return 0;
    else
        return 1;
    fi
}

#
# Check for the flag
#
check_for_flag()
{
    if [ -e ${1} ] ; then
        return 0;
    else
        return 1;
    fi
}

#
# Creates flag indicating the apps cache has been moved.
#
make_flag()
{
    echo "" > /Applications/OSX-RAMDisk.app/${1}
}

# ------------------------------------------------------
# Applications which needs the cache to be moved to RAM
# Add yours at the end.
# -------------------------------------------------------

#
# Google Chrome Cache
#
move_chrome_cache()
{
    if [ -d "/Users/${USER}/Library/Caches/Google/Chrome" ]; then
        if user_response "I found chrome. Do you want me to move its cache?" ; then
            close_app "Google Chrome"
            /bin/mkdir -p /tmp/Google/Chrome
            /bin/mv ~/Library/Caches/Google/Chrome/* /tmp/Google/Chrome/
            /bin/mkdir -pv ${USERRAMDISK}/Google/Chrome/Default
            /bin/mv /tmp/Google/Chrome/ ${USERRAMDISK}/Google/Chrome
            /bin/ln -v -s -f ${USERRAMDISK}/Google/Chrome/Default ~/Library/Caches/Google/Chrome/Default
            /bin/rm -rf /tmp/Google/Chrome
            # and let's create a flag for next run that we moved the cache.
            echo "";
        fi
    else
        echo "No Google chrome folder has been found. Skiping."
    fi
}

#
# Chrome Canary Cache
#
move_chrome_chanary_cache()
{
    if [ -d "/Users/${USER}/Library/Caches/Google/Chrome Canary" ]; then
        if user_response "I found Chrome Canary. Do you want move its cache?"; then
            close_app "Chrome Canary"
            /bin/rm -rf ~/Library/Caches/Google/Chrome\ Canary/*
            /bin/mkdir -p ${USERRAMDISK}/Google/Chrome\ Canary/Default
            /bin/ln -s ${USERRAMDISK}/Google/Chrome\ Canary/Default ~/Library/Caches/Google/Chrome\ Canary/Default
        fi
    fi
}

#
# Safari Cache
#
move_safari_cache()
{
    if [ -d "/Users/${USER}/Library/Caches/com.apple.Safari" ]; then
        if user_response "Do you want to move Safari cache?"; then
            close_app "Safari"
            /bin/rm -rf ~/Library/Caches/com.apple.Safari
            /bin/mkdir -p ${USERRAMDISK}/Apple/Safari
            /bin/ln -s ${USERRAMDISK}/Apple/Safari ~/Library/Caches/com.apple.Safari
            echo "Moved Safari cache."
        fi
    fi
}

#
# iTunes Cache
#
move_itunes_cache()
{
    if [ -d "/Users/${USER}/Library/Caches/com.apple.iTunes" ]; then
        close_app "iTunes"
        /bin/rm -rf /Users/${USER}/Library/Caches/com.apple.iTunes
        /bin/mkdir -pv ${USERRAMDISK}/Apple/iTunes
        /bin/ln -v -s ${USERRAMDISK}/Apple/iTunes ~/Library/Caches/com.apple.iTunes
        echo "Moved iTunes cache."
    fi
}

#
# Intellij Idea
#
# fixme - what if the version is not 14?
move_idea_cache()
{
    if [ -d "/Applications/IntelliJ IDEA 14.app" ]; then
        close_app "IntelliJ Idea 14"
        # make a backup of config - will need it when uninstalling
        cp -f /Applications/IntelliJ\ IDEA\ 14.app/Contents/bin/idea.properties /Applications/IntelliJ\ IDEA\ 14.app/Contents/bin/idea.properties.back
        # Idea will create those dirs
        echo "idea.system.path=${USERRAMDISK}/Idea" >> /Applications/IntelliJ\ IDEA\ 14.app/Contents/bin/idea.properties
        echo "idea.log.path=${USERRAMDISK}/Idea/logs" >> /Applications/IntelliJ\ IDEA\ 14.app/Contents/bin/idea.properties
        echo "Moved IntelliJ cache."
    fi
}

#
# Intellij Idea Community Edition
#
move_ideace_cache()
{
    # todo add other versions support and CE edition
    if [ -d "/Applications/IntelliJ IDEA 14 CE.app" ]; then
        close_app "IntelliJ Idea 14 CE"
        # make a backup of config - will need it when uninstalling
        cp -f /Applications/IntelliJ\ IDEA\ 14\ CE.app/Contents/bin/idea.properties /Applications/IntelliJ\ IDEA\ 14\ CE.app/Contents/bin/idea.properties.back
        # Idea will create those dirs
        echo "idea.system.path=${USERRAMDISK}/Idea" >> /Applications/IntelliJ\ IDEA\ 14\ CE.app/Contents/bin/idea.properties
        echo "idea.log.path=${USERRAMDISK}/Idea/logs" >> /Applications/IntelliJ\ IDEA\ 14\ CE.app/Contents/bin/idea.properties
        echo "Moved IntelliJ cache."
    fi
}

#
# Android Studio
#
move_android_studio_cache()
{
    close_app "Android Studio"
    echo "moving Android Studio cache";
    if [ -d "/Applications/Android Studio.app" ]; then
        # make a backup of config - will need it when uninstalling
        cp -f /Applications/Android\ Studio.app/Contents/bin/idea.properties /Applications/Android\ Studio.app/Contents/bin/idea.properties.back
        # Idea will create those dirs
        echo "idea.system.path=${USERRAMDISK}/AndroidStudio" >> /Applications/Android\ Studio.app/Contents/bin/idea.properties
        echo "idea.log.path=${USERRAMDISK}/AndroidStudio/logs" >> /Applications/Android\ Studio.app/Contents/bin/idea.properties
        echo "Moved Android cache."
    fi
}

#
# Clion
#
move_clion_cache()
{
    if [ -d "/Applications/Clion.app" ]; then
        if user_response "I found CLion. Do you want me to move its cache?" ; then
            echo "moving Clion cache";
            close_app "Clion"
            # make a backup of config - will need it when uninstalling
            cp -f /Applications/Clion.app/Contents/bin/idea.properties /Applications/Clion.app/Contents/bin/idea.properties.back
            # Idea will create those dirs
            echo "idea.system.path=${USERRAMDISK}/CLion" >> /Applications/Clion.app/Contents/bin/idea.properties
            echo "idea.log.path=${USERRAMDISK}/Clion/logs" >> /Applications/Clion.app/Contents/bin/idea.properties
            echo "Moved Clion cache."
        fi
    fi
}

#
# AppCode
#
move_appcode_cache()
{
    if [ -d "/Applications/AppCode.app" ]; then
        if user_response "I found AppCode. Do you want me to move its cache?" ; then
            echo "moving AppCode cache";
            close_app "AppCode"
            # make a backup of config - will need it when uninstalling
            cp -f /Applications/AppCode.app/Contents/bin/idea.properties /Applications/AppCode.app/Contents/bin/idea.properties.back
            # Need to create those dirs
            echo "idea.system.path=${USERRAMDISK}/AppCode" >> /Applications/AppCode.app/Contents/bin/idea.properties
            echo "idea.log.path=${USERRAMDISK}/AppCode/logs" >> /Applications/AppCode.app/Contents/bin/idea.properties
            mkdir -p ${USERRAMDISK}/AppCode/logs
            echo "Moved AppCode cache."
        fi
    fi
}


# -----------------------------------------------------------------------------------
# The entry point
# -----------------------------------------------------------------------------------
main() {
    check_requirements
    # and create our RAM disk
    mk_ram_disk
    # move the caches
    move_chrome_cache
    move_safari_cache
    move_idea_cache
    move_ideace_cache
    move_itunes_cache
    move_android_studio_cache
    move_clion_cache
    move_appcode_cache
    echo "All good - I have done my job. Your apps should fly."
}

main "$@"
# -----------------------------------------------------------------------------------
