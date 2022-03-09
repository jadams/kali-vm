#!/bin/sh

# XXX mostly taken from live-build-config, with some modifications

set -e

configure_sources_list() {
    echo > /etc/apt/sources.list

    if grep -q '^deb ' /etc/apt/sources.list; then
        echo "INFO: sources.list is configured, everything is fine"
        return
    fi

    echo "INFO: sources.list is empty, setting up a default one for Kali"

    cat >/etc/apt/sources.list <<END
# See https://www.kali.org/docs/general-use/kali-linux-sources-list-repositories/
deb http://http.kali.org/kali kali-rolling main contrib non-free

# Additional line for source packages
# deb-src http://http.kali.org/kali kali-rolling main contrib non-free
END
    apt-get update
}

get_user_list() {
    for user in $(cd /home && ls); do
        if ! getent passwd "$user" >/dev/null; then
            echo "WARNING: user '$user' is invalid but /home/$user exists"
            continue
        fi
        echo "$user"
    done
    echo "root"
}

configure_zsh() {
    if grep -q 'nozsh' /proc/cmdline; then
        echo "INFO: user opted out of zsh by default"
        return
    fi
    if [ ! -x /usr/bin/zsh ]; then
        echo "INFO: /usr/bin/zsh is not available"
        return
    fi
    for user in $(get_user_list); do
        echo "INFO: changing default shell of user '$user' to zsh"
        chsh --shell /usr/bin/zsh $user
    done
}

configure_usergroups() {
    addgroup --system kaboxer || true
    addgroup --system wireshark || true

    # adm - read access to log files
    # dialout - for serial access
    # kaboxer - for kaboxer
    # sudo - be root
    # wireshark - capture sessions in wireshark
    kali_groups="adm,dialout,kaboxer,sudo,wireshark"

    for user in $(get_user_list); do
        echo "INFO: adding user '$user' to groups '$kali_groups'"
        usermod -a -G "$kali_groups" $user || true
    done
}

configure_sources_list
configure_zsh
configure_usergroups