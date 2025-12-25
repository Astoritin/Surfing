#!/bin/sh

SKIPUNZIP=1
ASH_STANDALONE=1

LOCALE=$(getprop "persist.sys.locale")

SURFING_PATH="/data/adb/modules/Surfing"
SCRIPTS_PATH="/data/adb/box_bll/scripts"
NET_PATH="/data/misc/net"
CTR_PATH="/data/misc/net/rt_tables"
CONFIG_FILE="/data/adb/box_bll/clash/config.yaml"
BACKUP_FILE="/data/adb/box_bll/clash/proxies/subscribe_urls_backup.txt"
APK_FILE="$MODPATH/webroot/Web.apk"
INSTALL_DIR="/data/app"
HOSTS_FILE="/data/adb/box_bll/clash/etc/hosts"
HOSTS_PATH="/data/adb/box_bll/clash/etc"
HOSTS_BACKUP="/data/adb/box_bll/clash/etc/hosts.bak"

SURFING_TILE_ZIP="$MODPATH/SurfingTile.zip"
SURFING_TILE_DIR_UPDATE="/data/adb/modules/SurfingTile"
SURFING_TILE_DIR="/data/adb/modules_update/SurfingTile"

MODULE_PROP_PATH="/data/adb/modules/Surfing/module.prop"
MODULE_VERSION_CODE=$(grep_prop versionCode "$MODULE_PROP_PATH")

press_a_key_timeout=10

eco() {  # ec(h)o locale content

  if [ "$LOCALE" = "zh-CN" ] || [ "$LOCALE" = "zh-Hans-CN" ]; then
    ui_print " $1"
  else
    ui_print " $2"
  fi

}

ecol() {  # ec(h)o line

  length=28
  symbol=*

  line=$(printf "%-${length}s" | tr ' ' "$symbol")
  ui_print "$line"

}

ecoe() { ui_print " "; }  # ec(h)o empty line

if [ "$MODULE_VERSION_CODE" -lt 1638 ]; then
  INSTALL_TILE=true
else
  INSTALL_TILE=false
fi

if [ "$BOOTMODE" != true ]; then
  abort "Error: Please install via Magisk Manager / KernelSU Manager / APatch"
elif [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
  abort "Error: Please update your KernelSU Manager version"
fi

if [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10683 ]; then
  service_dir="/data/adb/ksu/service.d"
else
  service_dir="/data/adb/service.d"
fi

if [ ! -d "$service_dir" ]; then
  mkdir -p "$service_dir"
fi

extract_subscribe_urls() {
  if [ -f "$CONFIG_FILE" ]; then
    awk '/proxy-providers:/,/^profile:/' "$CONFIG_FILE" | \
    grep -Eo 'url: ".*"' | \
    sed -E 's/url: "(.*)"/\1/' | \
    sed 's/&/\\&/g' > "$BACKUP_FILE"
    
    if [ -s "$BACKUP_FILE" ]; then
      eco "已备份订阅地址至：" "Backed up the subscription URLs to:"
      ui_print " proxies/subscribe_urls_backup.txt"
    else
      eco "未找到 URLs，请检查配置文件格式" "No URLs found. Check config format."
    fi
  else
    eco "配置文件不存在，无法提取 URLs" "Config file missing. Cannot extract URLs."
  fi
}

restore_subscribe_urls() {
  if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
    awk 'NR==FNR {
           urls[++n] = $0; next
         }
         /proxy-providers:/ { inBlock = 1 }
         inBlock && /url: / {
           sub(/url: ".*"/, "url: \"" urls[++i] "\"")
         }
         /profile:/ { inBlock = 0 }
         { print }
        ' "$BACKUP_FILE" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    eco "已还原 URLs 至 config.yaml" "Restored URLs to config.yaml"
  else
    eco "找不到可用备份，已跳过还原" "No valid backup found. Skipped restore."
  fi
  ecoe
}

checkout_metamodule() {
    modules_dir="/data/adb/modules"
    modules_update_dir="/data/adb/modules_update"

    for moddir in "$modules_dir" "$modules_update_dir"; do
        [ -d "$moddir" ] || continue
        for current_module_dir in "$moddir"/*; do
            current_module_prop="$current_module_dir/module.prop"
            [ -e "$current_module_prop" ] || continue

            is_metamodule=$(grep_prop "metamodule" "$current_module_prop")
            current_module_name=$(grep_prop "name" "$current_module_prop")
            current_module_ver_name=$(grep_prop "version" "$current_module_prop")
            current_module_ver_code=$(grep_prop "versionCode" "$current_module_prop")
            case "$is_metamodule" in
                1|true ) [ ! -f "$current_module_dir/disable" ] && [ ! -f "$current_module_dir/remove" ] && return 0;;
            esac

        done
    done
    return 1
}

install_web_apk() {
  if [ -f "$APK_FILE" ]; then
    cp "$APK_FILE" "$INSTALL_DIR/"
    eco "正在安装 Web APK…" "Installing Web APK..."
    pm install "$INSTALL_DIR/Web.apk" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      eco "已安装" "Success"
    else
      eco "安装失败" "Failed"
    fi
    rm -rf "$INSTALL_DIR/Web.apk"
  else
    eco "未找到 Web.apk" "Web.apk not found"
  fi
  ecoe
}

install_surfingtile_apk() {
  APK_SRC="$SURFING_TILE_DIR/system/app/com.surfing.tile/com.surfing.tile.apk"
  APK_TMP="$INSTALL_DIR/com.surfing.tile.apk"
  if [ -f "$APK_SRC" ]; then
    cp "$APK_SRC" "$APK_TMP"
    eco "正在安装 SurfingTile APK…" "Installing SurfingTile APK..."
    pm install "$APK_TMP" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      eco "已安装" "Success"
    else
      eco "安装失败" "Failed"
    fi
    rm -f "$APK_TMP"
  else
    eco "未找到 SurfingTile APK" "SurfingTile APK not found"
  fi
  ecoe
}

install_surfingtile_module() {
  mkdir -p "$SURFING_TILE_DIR"
  mkdir -p "$SURFING_TILE_DIR_UPDATE"

  unzip -o "$SURFING_TILE_ZIP" -d "$SURFING_TILE_DIR" >/dev/null 2>&1

  cp -f "$SURFING_TILE_DIR/module.prop" "$SURFING_TILE_DIR_UPDATE"
  touch "$SURFING_TILE_DIR_UPDATE/update"

  if [ "$KSU" = true ] && [ "$KSU_VER_CODE" -ge 22098 ]; then
      ecoe
      eco "检测到当前 KernelSU 版本正在使用" "Detect current KernelSU is using meta-module feature"
      eco "元模块功能，若要 SurfingTile 模块生效" "Make sure you have installed meta-module"
      eco "请务必确保已安装元模块!" "if you want SurfingTile module to take effect!"
      ecoe
      eco "注意：如果你不知道元模块是什么" "NOTICE: If you don’t know what is meta-module,"
      eco "请查阅 KernelSU 官方网站" "please check KernelSU official website"
      ecoe
      if ! checkout_metamodule; then
        eco "警告：未检测到任何元模块存在" "WARN: No meta-module detect"
        eco "SurfingTile 可能无法正常挂载为系统应用" "SurfingTile may not be mounted as system app"
      else
        eco "检测到当前元模块：" "Detect current meta-module: "
        ui_print " ${current_module_name} ${current_module_ver_name} (${current_module_ver_code})"
      fi
      ecoe
  fi
}

install_surfingtile() {

  install_surfingtile_module
  install_surfingtile_apk

}

choose_volume_key() {
    sleep 0.5
    eco "等待按键中 (${press_a_key_timeout}秒)" "Waiting for pressing key (${press_a_key_timeout}s)..."

    read -r -t $press_a_key_timeout line < <(getevent -ql | awk '/KEY_VOLUME/ {print; exit}')

    ecoe
    if [ $? -eq 142 ]; then
        eco "未检测到按键，执行默认选项…" "No input detected. Running default option..."
        return 1
    fi

    if echo "$line" | grep -q "KEY_VOLUMEUP"; then
        return 0
    else
        return 1
    fi
}

choose_to_umount_hosts_file() {
  ecol
  ecoe
  eco "是否挂载 hosts 文件至系统？" "Mount the hosts file to the system ?"
  ecoe
  eco "音量增加键：挂载" "Volume Up: Mount"
  eco "音量减少键：卸载 (默认)" "Volume Down: Uninstall (default)"

  if choose_volume_key; then
    eco "已挂载 hosts 文件" "Hosts file mounted"
  else
    eco "已卸载 hosts 文件" "Uninstalling hosts file is complete"
    rm -f "$HOSTS_FILE"
  fi
  ecoe

}

choose_to_install_surfingtile() {
  ecol
  ecoe
  eco "是否安装 SurfingTile APP?" "Install SurfingTile APP?"
  ecoe
  eco "音量增加键：否" "Volume Up: No"
  eco "音量减少键：是 (默认)" "Volume Down: Yes (default)"

  if choose_volume_key; then
    eco "已跳过安装 SurfingTile APP…" "Skip installing SurfingTile APP..."
    ecoe
  else
    install_surfingtile
  fi
}

choose_to_install_web_apk() {
  ecol
  ecoe
  eco "是否安装 Web APP?" "Install Web APP?"
  ecoe
  eco "音量增加键：否" "Volume Up: No"
  eco "音量减少键：是 (默认)" "Volume Down: Yes (default)"

  if choose_volume_key; then
    eco "已跳过安装 Web APP…" "Skip installing Web APP..."
    ecoe
  else
    install_Web_apk
  fi
}

remove_old_surfingtile() {
  OLD_TILE_MODDIR="/data/adb/modules/Surfingtile"
  OLD_TILE_APP="$(pm path "com.yadli.surfingtile" 2>/dev/null | sed 's/package://')"

  if [ -d "$OLD_TILE_MODDIR" ]; then
    eco "正在卸载旧版本 SurfingTile 模块…" "Uninstalling old SurfingTile module..."
    touch "${OLD_TILE_MODDIR}/remove" && eco "重启后完成卸载" "Reboot to take effect"
  fi

  if [ -n "$OLD_TILE_APP" ]; then
    eco "正在卸载旧版本 SurfingTile APP…" "Uninstalling old SurfingTile APP..."
    pm uninstall "com.yadli.surfingtile" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      eco "已卸载" "Success"
    else
      eco "卸载失败" "Failed"
    fi
  fi
}

unzip -qo "${ZIPFILE}" -x 'META-INF/*' -d "$MODPATH"

if [ -z "$LOCALE" ]; then
  ecoe
  ui_print " 请选择你所使用的语言：
 Please select your language:
 
 音量增加键：简体中文
 Volume Up: Simplified Chinese
 音量减少键：English (默认)
 Volume Down: English (default)

 等待按键中 (${press_a_key_timeout}秒)"
  if choose_volume_key; then
    LOCALE="zh-CN"
  else
    LOCALE="en-US"
  fi
fi

eco "欢迎使用 Surfing" "Welcome to Surfing"
remove_old_surfingtile

if [ -d /data/adb/box_bll ]; then
  eco "更新中…" "Updating..."
  ui_print " ↴"
  ecol
  ecoe
  eco "正在初始化服务…" "Initializing services..."
  /data/adb/box_bll/scripts/box.service stop > /dev/null 2>&1
  sleep 1.5
  ecoe

  SURFING_TILE_MODULE_PROP_ZIP="${SURFING_TILE_DIR}/module.prop"
  SURFING_TILE_MODULE_PROP_INSTALLED="${SURFING_TILE_DIR_UPDATE}/module.prop"

  SURFING_TILE_VER_ZIP=$(grep_prop versionCode "$SURFING_TILE_MODULE_PROP_ZIP")
  SURFING_TILE_VER_INSTALLED=$(grep_prop versionCode "$SURFING_TILE_MODULE_PROP_INSTALLED")

  [ -z "$SURFING_TILE_VER_INSTALLED" ] && SURFING_TILE_VER_INSTALLED=0

  if [ "$INSTALL_TILE" = true ]; then
    rm -rf /data/adb/modules/Surfingtile 2>/dev/null
    rm -rf /data/adb/modules/Surfing_Tile 2>/dev/null
    install_surfingtile
  elif [ "$SURFING_TILE_VER_ZIP" -gt "$SURFING_TILE_VER_INSTALLED" ]; then
    eco "检测到旧版本 SurfingTile 模块" "Detect old version of SurfingTile module"
    eco "升级中…" "Updating..."
    install_surfingtile
  elif [ "$SURFING_TILE_VER_INSTALLED" -eq 0 ]; then
    eco "未检测到 SurfingTile 模块" "SurfingTile module is not found"
    ecoe
    choose_to_install_surfingtile
  else
    eco "已安装的 SurfingTile 模块版本" "Installed SurfingTile module version"
    eco "≥ 当前模块 zip 内置的版本" "is higher than/same as current module zip inbuilt version"
    eco "无需更新 SurfingTile 模块" "Update SurfingTile module is not needed"
    ecoe
  fi

  extract_subscribe_urls

  if [ -f "$HOSTS_FILE" ]; then
    cp -f "$HOSTS_FILE" "$HOSTS_BACKUP"
  fi

  mkdir -p "$HOSTS_PATH"
  touch "$HOSTS_FILE"
  
  cp /data/adb/box_bll/clash/config.yaml /data/adb/box_bll/clash/config.yaml.bak
  cp /data/adb/box_bll/scripts/box.config /data/adb/box_bll/scripts/box.config.bak
  cp -f "$MODPATH/box_bll/clash/config.yaml" /data/adb/box_bll/clash/
  cp -f "$MODPATH/box_bll/clash/Toolbox.sh" /data/adb/box_bll/clash/  
  cp -f "$MODPATH/box_bll/scripts/"* /data/adb/box_bll/scripts/
  
  restore_subscribe_urls

  for pid in $(pidof inotifyd); do
    if grep -qE "box.inotify|net.inotify|ctr.inotify" /proc/${pid}/cmdline; then
      kill "$pid"
    fi
  done
  nohup inotifyd "${SCRIPTS_PATH}/box.inotify" "$HOSTS_PATH" > /dev/null 2>&1 &
  nohup inotifyd "${SCRIPTS_PATH}/box.inotify" "$SURFING_PATH" > /dev/null 2>&1 &
  nohup inotifyd "${SCRIPTS_PATH}/net.inotify" "$NET_PATH" > /dev/null 2>&1 &
  nohup inotifyd "${SCRIPTS_PATH}/ctr.inotify" "$CTR_PATH" > /dev/null 2>&1 &
  sleep 1
  cp -f "$MODPATH/box_bll/clash/etc/hosts" /data/adb/box_bll/clash/etc/
  rm -rf /data/adb/box_bll/clash/Model.bin
  rm -rf /data/adb/box_bll/clash/smart_weight_data.csv
  rm -rf /data/adb/box_bll/scripts/box.upgrade
  rm -rf "$MODPATH/box_bll"

  choose_to_umount_hosts_file
  
  sleep 1
  ecol
  ecoe
  eco "正在重启服务…" "Restarting service..."
  /data/adb/box_bll/scripts/box.service start > /dev/null 2>&1
  eco "更新完成，无需重启" "Update completed. No need to reboot."
  ecoe
else
  eco "安装中…" "Installing..."
  ui_print " ↴"
  mv "$MODPATH/box_bll" /data/adb/
  choose_to_install_surfingtile
  choose_to_install_web_apk
  ecol
  ecoe
  eco "模块安装完毕，工作目录为：" "Module installation completed. Working directory:"
  ui_print " /data/adb/box_bll/"
  ecoe
  eco "请在该工作目录下的 config.yaml" "Please add your subscription to"
  eco "添加你的订阅地址" "config.yaml under the working directory"
  ecoe
  eco "首次安装完成后需要重启" "A reboot is required after first installation"
  ecoe

  choose_to_umount_hosts_file
  
fi

if [ "$KSU" = true ]; then
  sed -i 's/name=Surfingmagisk/name=SurfingKernelSU/g' "$MODPATH/module.prop"
fi

if [ "$APATCH" = true ]; then
  sed -i 's/name=Surfingmagisk/name=SurfingAPatch/g' "$MODPATH/module.prop"
fi

mv -f "$MODPATH/Surfing_service.sh" "$service_dir/"
rm -f "$SURFING_TILE_ZIP"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$SURFING_TILE_DIR" 0 0 0755 0644
set_perm_recursive /data/adb/box_bll/ 0 3005 0755 0644
set_perm_recursive /data/adb/box_bll/scripts/ 0 3005 0755 0700
set_perm_recursive /data/adb/box_bll/bin/ 0 3005 0755 0700
set_perm_recursive /data/adb/box_bll/clash/etc/ 0 0 0755 0644
set_perm "$service_dir/Surfing_service.sh" 0 0 0700

chmod ugo+x /data/adb/box_bll/scripts/*

rm -f customize.sh