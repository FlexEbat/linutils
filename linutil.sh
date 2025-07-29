#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт необходимо запускать с правами суперпользователя (sudo)."
   exit 1
fi
if ! command -v gum &> /dev/null; then
    echo "gum не найден. Пожалуйста, установите его для работы скрипта."
    echo "Инструкции: https://github.com/charmbracelet/gum"
    exit 1
fi

if command -v apt &> /dev/null; then PKG_MANAGER="apt"
elif command -v dnf &> /dev/null; then PKG_MANAGER="dnf"
elif command -v pacman &> /dev/null; then PKG_MANAGER="pacman"
elif command -v emerge &> /dev/null; then PKG_MANAGER="emerge"
else
    gum style --bold --foreground="red" "Ошибка: Не удалось определить менеджер пакетов."
    exit 1
fi

INIT_SYSTEM="none"
if command -v systemctl &> /dev/null && systemctl is-system-running &> /dev/null; then
    INIT_SYSTEM="systemd"
elif command -v rc-update &> /dev/null; then
    INIT_SYSTEM="openrc"
fi

TITLE=$(gum style --padding "1 2" --border "rounded" --border-foreground "212" "Системный менеджер | $PKG_MANAGER | $INIT_SYSTEM")

execute_command() {
    local title="$1"
    local command_to_run="$2"

    if [[ "$PKG_MANAGER" == "apt" ]];
    then
        command_to_run="DEBIAN_FRONTEND=noninteractive $command_to_run"
        clear; echo "$TITLE"; gum style --bold "$title"
        gum style --foreground="240" -- "--- Начало вывода apt. Процесс может занять некоторое время. ---"; echo
        bash -c "$command_to_run"
        echo; gum style --foreground="240" -- "--- Конец вывода apt. ---"
    else
        clear; echo "$TITLE"; gum style --bold "$title"
        gum style --foreground="240" "Вывод команды будет показан ниже. Нажмите 'q' для выхода из просмотра после завершения."; sleep 2
        bash -c "$command_to_run" 2>&1 | gum pager
    fi
    gum style --bold --foreground="green" "✔ Действие завершено."
    gum input --placeholder="Нажмите Enter, чтобы вернуться в меню..." > /dev/null
}
is_pkg_available() {
    local pkg_name="$1"
    case $PKG_MANAGER in
        apt)    apt-cache show "$pkg_name" &> /dev/null ;;
        dnf)    dnf list available "$pkg_name" &> /dev/null ;;
        pacman) pacman -Si "$pkg_name" &> /dev/null ;;
        emerge) emerge --search --searchdesc "^$pkg_name$" | grep -q . ;;
    esac
    return $?
}
show_manual_system_info() {
    os_name=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2); kernel=$(uname -r); cpu=$(lscpu | grep "Model name" | sed 's/.*Model name:\s*//'); mem_used=$(free -h | grep Mem | awk '{print $3}'); mem_total=$(free -h | grep Mem | awk '{print $2}')
    info_block=$(gum join --vertical "$(gum style --bold 'ОС:') $os_name" "$(gum style --bold 'Ядро:') $kernel" "$(gum style --bold 'Процессор:') $cpu" "$(gum style --bold 'Память:') $mem_used / $mem_total" "$(gum style --bold 'Пакетный менеджер:') $PKG_MANAGER" "$(gum style --bold 'Система инициализации:') $INIT_SYSTEM")
    echo; echo "$info_block" | gum style --border="rounded" --padding="1 2"
}


install_desktop() {
    clear; echo "$TITLE"; gum style --bold "Установка Окружения Рабочего Стола (DE/WM)"
    CHOICE=$(gum choose "GNOME" "KDE Plasma" "XFCE4" "i3" "Sway" "Hyprland" "LXDE" "Назад")
    [[ -z "$CHOICE" || "$CHOICE" == "Назад" ]] && return
    
    local desktop_pkg="" friendly_name="$CHOICE"
    case "$CHOICE" in
        "GNOME") case $PKG_MANAGER in apt) desktop_pkg="gnome";; dnf) desktop_pkg="@gnome-desktop";; pacman) desktop_pkg="gnome";; emerge) desktop_pkg="gnome-base/gnome";; esac;;
        "KDE Plasma") case $PKG_MANAGER in apt) desktop_pkg="kde-standard";; dnf) desktop_pkg="@kde-desktop";; pacman) desktop_pkg="plasma";; emerge) desktop_pkg="kde-plasma/plasma-meta";; esac;;
        "XFCE4") case $PKG_MANAGER in apt) desktop_pkg="xfce4";; dnf) desktop_pkg="@xfce-desktop-environment";; pacman) desktop_pkg="xfce4";; emerge) desktop_pkg="xfce-base/xfce4-meta";; esac;;
        "i3") friendly_name="i3 (с панелью и лаунчером)"; case $PKG_MANAGER in apt) desktop_pkg="i3 i3status rofi";; dnf) desktop_pkg="i3 i3status rofi";; pacman) desktop_pkg="i3 i3status rofi";; emerge) desktop_pkg="x11-wm/i3 x11-misc/i3status x11-misc/rofi";; esac;;
        "Sway") desktop_pkg="sway";;
        "LXDE") case $PKG_MANAGER in apt) desktop_pkg="lxde";; dnf) desktop_pkg="@lxde-desktop";; pacman) desktop_pkg="lxde";; emerge) desktop_pkg="lxde-base/lxde-meta";; esac;;
        "Hyprland") friendly_name="Hyprland (с базовыми утилитами)"; case $PKG_MANAGER in pacman) desktop_pkg="hyprland waybar wofi kitty mako swaybg swaylock";; emerge) desktop_pkg="gui-wm/hyprland gui-apps/waybar gui-apps/wofi x11-terms/kitty x11-misc/mako gui-apps/swaybg gui-apps/swaylock";; *) clear; echo "$TITLE"; gum style --border="double" --padding="1 2" --border-foreground="yellow" "ВНИМАНИЕ: Hyprland отсутствует в стандартных репозиториях!" $'\n\nУстановка на вашей системе требует подключения сторонних репозиториев или сборки из исходников.' $'\nПожалуйста, обратитесь к официальной документации Hyprland для вашего дистрибутива.'; gum input --placeholder="Нажмите Enter..." > /dev/null; return;; esac;;
    esac
    local confirmation_header=$(gum style --bold "Подтверждение установки")
    local package_list_formatted=$(echo "$desktop_pkg" | tr ' ' '\n' | sed 's/^/• /' | gum style --padding "0 2" --foreground 212)
    local prompt_text="$confirmation_header"$'\n\n'"Будет установлено '$friendly_name':"$'\n'"$package_list_formatted"$'\n'"Продолжить?"
    if gum confirm --affirmative="Установить" --negative="Назад" "$prompt_text"; then
        local install_cmd; if [[ $PKG_MANAGER == "dnf" && ("$CHOICE" == "GNOME" || "$CHOICE" == "KDE Plasma" || "$CHOICE" == "XFCE4" || "$CHOICE" == "LXDE") ]]; then install_cmd="dnf groupinstall -y $desktop_pkg"; else case $PKG_MANAGER in apt) install_cmd="apt install -y $desktop_pkg";; dnf) install_cmd="dnf install -y $desktop_pkg";; pacman) install_cmd="pacman --noconfirm -S $desktop_pkg";; emerge) install_cmd="emerge --ask $desktop_pkg";; esac; fi
        execute_command "Установка $friendly_name..." "$install_cmd"
    fi
}
install_components() {
    clear; echo "$TITLE"; gum style --bold "Установка системных компонентов"
    gum style --foreground="240" "Используйте ПРОБЕЛ для выбора, ENTER для подтверждения. Для отмены и выхода нажмите ESC."
    case $PKG_MANAGER in
        apt) x_pkgs="xserver-xorg"; wayland_pkgs="wayland-protocols libwayland-dev"; pipewire_pkgs="pipewire pipewire-pulse wireplumber"; nvidia_pkgs="nvidia-driver"; amd_pkgs="xserver-xorg-video-amdgpu mesa-vulkan-drivers"; intel_pkgs="xserver-xorg-video-intel mesa-vulkan-drivers"; gaming_pkgs="steam";;
        dnf) x_pkgs="xorg-x11-server-Xorg"; wayland_pkgs="wayland-devel"; pipewire_pkgs="pipewire pipewire-pulseaudio wireplumber"; nvidia_pkgs="akmod-nvidia"; amd_pkgs="xorg-x11-drv-amdgpu mesa-vulkan-drivers"; intel_pkgs="xorg-x11-drv-intel mesa-vulkan-drivers"; gaming_pkgs="steam";;
        pacman) x_pkgs="xorg-server"; wayland_pkgs="wayland"; pipewire_pkgs="pipewire pipewire-pulse wireplumber"; nvidia_pkgs="nvidia"; amd_pkgs="xf86-video-amdgpu vulkan-radeon"; intel_pkgs="xf86-video-intel vulkan-intel"; gaming_pkgs="steam";;
        emerge) x_pkgs="x11-base/xorg-server"; wayland_pkgs="dev-libs/wayland"; pipewire_pkgs="media-video/pipewire"; nvidia_pkgs="x11-drivers/nvidia-drivers"; amd_pkgs="x11-drivers/xf86-video-amdgpu"; intel_pkgs="x11-drivers/xf86-video-intel"; gaming_pkgs="games-util/steam-launcher";;
    esac
    
    PRESET_CHOICES=$(gum choose --no-limit "Графический сервер X.Org" "Базовые библиотеки Wayland" "Аудио-сервер PipeWire" "Драйверы NVIDIA" "Драйверы AMD" "Драйверы Intel" "Gaming (Steam + Multilib)")
    if [[ $? -ne 0 || -z "$PRESET_CHOICES" ]]; then return; fi
    
    packages_to_install=""; while IFS= read -r choice; do case "$choice" in "Графический сервер X.Org") packages_to_install+="$x_pkgs ";; "Базовые библиотеки Wayland") packages_to_install+="$wayland_pkgs ";; "Аудио-сервер PipeWire") packages_to_install+="$pipewire_pkgs ";; "Драйверы NVIDIA") packages_to_install+="$nvidia_pkgs ";; "Драйверы AMD") packages_to_install+="$amd_pkgs ";; "Драйверы Intel") packages_to_install+="$intel_pkgs ";; "Gaming"*) case "$PKG_MANAGER" in "apt") gum spin --spinner dot --title="Включаю i386..." -- bash -c "dpkg --add-architecture i386 && apt update"; packages_to_install+="$gaming_pkgs ";; "pacman") if ! grep -q "^\s*\[multilib\]" /etc/pacman.conf; then clear; echo "$TITLE"; gum style --border="double" --padding="1 2" --border-foreground="red" "ВНИМАНИЕ: [multilib] не включен!" $'\n\n1. Откройте: sudo nano /etc/pacman.conf' $'\n2. Раскомментируйте [multilib] и строку Include под ним.' $'\n3. Выполните: sudo pacman -Syu'; gum input --placeholder="Нажмите Enter..." > /dev/null; else packages_to_install+="$gaming_pkgs "; fi;; *) packages_to_install+="$gaming_pkgs ";; esac;; esac; done <<< "$PRESET_CHOICES"
    packages_to_install=$(echo ${packages_to_install% }); [[ -z "$packages_to_install" ]] && return
    local confirmation_header=$(gum style --bold "Подтверждение установки"); local package_list_formatted=$(echo "$packages_to_install" | tr ' ' '\n' | sed 's/^/• /' | gum style --padding "0 2" --foreground 212); local prompt_text="$confirmation_header"$'\n\n'"Будут установлены компоненты:"$'\n'"$package_list_formatted"$'\n'"Продолжить?"
    if gum confirm --affirmative="Установить" --negative="Назад" "$prompt_text"; then local install_cmd; case $PKG_MANAGER in apt) install_cmd="apt install -y $packages_to_install";; dnf) install_cmd="dnf install -y $packages_to_install";; pacman) install_cmd="pacman --noconfirm -S $packages_to_install";; emerge) install_cmd="emerge --ask $packages_to_install";; esac; execute_command "Установка компонентов..." "$install_cmd"; fi
}
install_by_name() {
    clear; echo "$TITLE"; gum style --bold "Установка пакетов по названию"; PACKAGES=$(gum input --placeholder "Введите пакеты через пробел...");
    if [[ -n "$PACKAGES" ]]; then
        clear; echo "$TITLE"; local confirmation_header=$(gum style --bold "Подтверждение установки"); local package_list_formatted=$(echo "$PACKAGES" | tr ' ' '\n' | sed 's/^/• /' | gum style --padding "0 2" --foreground 212); local prompt_text="$confirmation_header"$'\n\n'"Будут установлены пакеты:"$'\n'"$package_list_formatted"$'\n'"Продолжить?";
        if gum confirm --affirmative="Установить" --negative="Назад" "$prompt_text"; then local install_cmd; case $PKG_MANAGER in apt) install_cmd="apt install -y $PACKAGES";; dnf) install_cmd="dnf install -y $PACKAGES";; pacman) install_cmd="pacman --noconfirm -S $PACKAGES";; emerge) install_cmd="emerge --ask $PACKAGES";; esac; execute_command "Установка пакетов..." "$install_cmd"; fi
    fi
}
install_menu() { while true; do clear; echo "$TITLE"; CHOICE=$(gum choose "Установить Окружение Рабочего Стола (DE/WM)" "Установить системные компоненты (Пресеты)" "Установить пакет по названию" "Назад"); case "$CHOICE" in "Установить Окружение Рабочего Стола (DE/WM)") install_desktop;; "Установить системные компоненты (Пресеты)") install_components;; "Установить пакет по названию") install_by_name;; "Назад" | *) break;; esac; done; }

remove_packages() {
    clear; echo "$TITLE"; gum style --bold "Удаление пакетов"
    gum style --foreground="240" "Начните вводить имя для поиска. Используйте TAB для выбора нескольких пакетов, затем нажмите ENTER."
    local list_cmd; case $PKG_MANAGER in apt) list_cmd="apt list --installed 2>/dev/null | awk -F/ '{print \$1}' | tail -n +2";; dnf) list_cmd="dnf list installed 2>/dev/null | awk '{print \$1}' | tail -n +2 | sed 's/\.[^.]*\$//'";; pacman) list_cmd="pacman -Qqe";; emerge) list_cmd="qlist -I | awk -F/ '{print \$2}'";; esac
    installed_list=$(gum spin --spinner dot --title "Получение списка..." -- bash -c "$list_cmd");
    PACKAGES_TO_REMOVE=$(echo "$installed_list" | gum filter --no-limit --placeholder="Поиск...")
    if [[ $? -ne 0 || -z "$PACKAGES_TO_REMOVE" ]]; then return; fi
    
    PACKAGES_TO_REMOVE_CMD=$(echo "$PACKAGES_TO_REMOVE" | tr '\n' ' '); local package_list_formatted=$(echo "$PACKAGES_TO_REMOVE" | sed 's/^/• /' | gum style --padding "0 2" --foreground="red"); local confirmation_header=$(gum style --bold "Подтверждение удаления"); local prompt_text="$confirmation_header"$'\n\n'"Будут удалены пакеты:"$'\n'"$package_list_formatted"$'\n'"Продолжить?";
    if gum confirm --affirmative="Удалить" --negative="Назад" "$prompt_text"; then local remove_cmd; case $PKG_MANAGER in apt) remove_cmd="apt purge --auto-remove -y $PACKAGES_TO_REMOVE_CMD";; dnf) remove_cmd="dnf remove -y $PACKAGES_TO_REMOVE_CMD && dnf autoremove -y";; pacman) remove_cmd="pacman --noconfirm -Rns $PACKAGES_TO_REMOVE_CMD";; emerge) remove_cmd="emerge --depclean --ask $PACKAGES_TO_REMOVE_CMD";; esac; execute_command "Удаление пакетов..." "$remove_cmd"; fi
}

service_management_menu() {
    local service_list_cmd action_cmd service_name
    while true; do
        clear; echo "$TITLE"; gum style --bold "Управление службами ($INIT_SYSTEM)"
        CHOICE=$(gum choose "Показать активные службы" "Показать все службы" "Управление службой" "Назад")
        case "$CHOICE" in
            "Показать активные службы") if [[ "$INIT_SYSTEM" == "systemd" ]]; then service_list_cmd="systemctl list-units --type=service --state=running"; else service_list_cmd="rc-status --servicelist"; fi; bash -c "$service_list_cmd" | gum pager;;
            "Показать все службы") if [[ "$INIT_SYSTEM" == "systemd" ]]; then service_list_cmd="systemctl list-unit-files --type=service"; else service_list_cmd="rc-update -v show"; fi; bash -c "$service_list_cmd" | gum pager;;
            "Управление службой")
                if [[ "$INIT_SYSTEM" == "systemd" ]]; then service_list_cmd="systemctl list-unit-files --type=service | awk '{print \$1}' | tail -n +2 | head -n -2"; else service_list_cmd="rc-update -v show | awk '{print \$1}'"; fi
                service_name=$(bash -c "$service_list_cmd" | gum filter --placeholder="Выберите службу..."); [[ -z "$service_name" ]] && continue
                ACTION=$(gum choose "Включить при загрузке" "Отключить при загрузке" "Запустить сейчас" "Остановить сейчас" "Показать статус" "Назад")
                case "$ACTION" in
                    "Включить при загрузке") if [[ "$INIT_SYSTEM" == "systemd" ]]; then action_cmd="systemctl enable $service_name"; else action_cmd="rc-update add $service_name default"; fi;;
                    "Отключить при загрузке") if [[ "$INIT_SYSTEM" == "systemd" ]]; then action_cmd="systemctl disable $service_name"; else action_cmd="rc-update del $service_name default"; fi;;
                    "Запустить сейчас") if [[ "$INIT_SYSTEM" == "systemd" ]]; then action_cmd="systemctl start $service_name"; else action_cmd="rc-service $service_name start"; fi;;
                    "Остановить сейчас") if [[ "$INIT_SYSTEM" == "systemd" ]]; then action_cmd="systemctl stop $service_name"; else action_cmd="rc-service $service_name stop"; fi;;
                    "Показать статус") if [[ "$INIT_SYSTEM" == "systemd" ]]; then action_cmd="systemctl status $service_name"; else action_cmd="rc-service $service_name status"; fi;;
                    "Назад" | *) continue ;;
                esac
                execute_command "Выполнение: $ACTION..." "$action_cmd";;
            "Назад" | *) break ;;
        esac
    done
}


system_info() {
    clear; echo "$TITLE"; gum style --bold "Информация о системе"
    if command -v neofetch &> /dev/null; then neofetch
    elif command -v fastfetch &> /dev/null; then fastfetch
    else
        if gum confirm "Утилита для вывода информации не найдена. Хотите установить fastfetch/neofetch?"; then
            local pkg_to_install=""; if is_pkg_available "fastfetch"; then pkg_to_install="fastfetch"; elif is_pkg_available "neofetch"; then pkg_to_install="neofetch"; fi
            if [[ -n "$pkg_to_install" ]]; then
                local install_cmd; case $PKG_MANAGER in apt) install_cmd="apt install -y $pkg_to_install";; dnf) install_cmd="dnf install -y $pkg_to_install";; pacman) install_cmd="pacman --noconfirm -S $pkg_to_install";; emerge) install_cmd="emerge --ask $pkg_to_install";; esac
                execute_command "Установка $pkg_to_install..." "$install_cmd"
                if command -v "$pkg_to_install" &> /dev/null; then clear; echo "$TITLE"; gum style --bold "Информация о системе"; "$pkg_to_install"; fi
            else
                gum style --foreground="red" "Ни fastfetch, ни neofetch не найдены в ваших репозиториях."; sleep 2
                show_manual_system_info
            fi
        else
            show_manual_system_info
        fi
    fi
    echo; gum input --placeholder="Нажмите Enter для возврата в меню..." > /dev/null
}

update_system() {
    clear; echo "$TITLE"
    if gum confirm "Выполнить полное обновление системы?" --affirmative="Да, обновить" --negative="Нет, назад"; then
        local update_cmd; case $PKG_MANAGER in apt) update_cmd="apt update && apt full-upgrade -y && apt autoremove -y";; dnf) update_cmd="dnf upgrade -y && dnf autoremove -y";; pacman) update_cmd="pacman --noconfirm -Syu";; emerge) update_cmd="emerge --sync && emerge -uDNav @world && emerge --depclean --ask";; esac
        execute_command "Обновление системы..." "$update_cmd"
    fi
}

while true; do
    clear; echo "$TITLE"
    main_menu_options=("Установка пакетов" "Удаление пакетов" "Обновление системы")
    if [[ "$INIT_SYSTEM" != "none" ]]; then main_menu_options+=("Управление службами ($INIT_SYSTEM)"); fi
    main_menu_options+=("Информация о системе" "Выход")
    CHOICE=$(gum choose "${main_menu_options[@]}")
    case "$CHOICE" in
        "Установка пакетов") install_menu ;;
        "Удаление пакетов") remove_packages ;;
        "Обновление системы") update_system ;;
        "Управление службами"*) service_management_menu ;;
        "Информация о системе") system_info ;;
        "Выход" | *) clear; exit 0 ;;
    esac
done
