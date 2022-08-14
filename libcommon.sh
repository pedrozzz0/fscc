#!/system/bin/sh
# KTSR™ by Pedro (pedrozzz0 @ GitHub)
# Credits: Ktweak, by Draco (tytydraco @ GitHub), LSpeed, qti-mem-opt & Uperf, by Matt Yang (yc9559 @ CoolApk) and Pandora's Box, by Eight (dlwlrma123 @ GitHub)
# If you wanna use the code as part of your project, please maintain the credits to it's respectives authors

#####################
# Variables
#####################
sys_frm="/system/framework"
sys_lib="/system/lib64"
vdr_lib="/vendor/lib64"
dvk="/data/dalvik-cache"
apx1="/apex/com.android.art/javalib"
apx2="/apex/com.android.runtime/javalib"
fscc_file_list=""
fscc_log="/data/media/0/ktsr/fscc.log"

log_i() {
	echo "[$(date +%T)]: [*] $1" >>"$fscc_log"
	echo "" >>"$fscc_log"
}

log_d() {
	echo "$1" >>"$fscc_log"
	echo "$1"
}

log_e() {
	echo "[!] $1" >>"$fscc_log"
	echo "[!] $1"
}

notif_start() { su -lp 2000 -c "cmd notification post -S bigtext -t 'FSCC is executing' tag 'FSCC is running...'" >/dev/null 2>&1; }

notif_end() { su -lp 2000 -c "cmd notification post -S bigtext -t 'FSCC is executing' tag 'FSCC pinned libs successfully!'" >/dev/null 2>&1; }

# Check for root permissions and bail if not granted
[[ "$(id -u)" != "0" ]] && {
	log_e "No root permissions. Exiting..."
	exit 1
}

# $1:apk_path $return:oat_path
# OPSystemUI/OPSystemUI.apk -> OPSystemUI/oat
fscc_path_apk_to_oat() { echo "${1%/*}/oat"; }

# $1:file/dir
# Only append if object isn't already on file list
fscc_list_append() { [[ ! "$fscc_file_list" == *"$1"* ]] && fscc_file_list="$fscc_file_list $1"; }

# Only append if object doesn't already exists either on pinner service to avoid unnecessary memory expenses
fscc_add_obj() {
	[[ "$sdk" -lt "24" ]] && fscc_list_append "$1" || {
		while IFS= read -r obj; do
			[[ "$1" != "$obj" ]] && fscc_list_append "$1"
		done <<<"$(dumpsys pinner | grep -E -i "$1" | awk '{print $1}')"
	}
}

# $1:package_name
# pm path -> "package:/system/product/priv-app/OPSystemUI/OPSystemUI.apk"
fscc_add_apk() { [[ "$1" != "" ]] && fscc_add_obj "$(pm path "$1" | head -1 | cut -d: -f2)"; }

# $1:package_name
fscc_add_dex() {
	[[ "$1" != "" ]] \
		&& {
			# pm path -> "package:/system/product/priv-app/OPSystemUI/OPSystemUI.apk"
			package_apk_path="$(pm path "$1" | head -1 | cut -d: -f2)"
			# User app: OPSystemUI/OPSystemUI.apk -> OPSystemUI/oat
			fscc_add_obj "${package_apk_path%/*}/oat"
			# Remove apk name suffix
			apk_nm="${package_apk_path%/*}"
			# Remove path prefix
			apk_nm="${apk_nm##*/}"
			# System app: get dex & vdex
			# /data/dalvik-cache/arm64/system@product@priv-app@OPSystemUI@OPSystemUI.apk@classes.dex
		}
	for dex in $(find "$dvk" | grep "@$apk_name@"); do
		fscc_add_obj "$dex"
	done
}

fscc_add_app_home() {
	# Well, not working on Android 7.1
	intent_act="android.intent.action.MAIN"
	intent_cat="android.intent.category.HOME"
	# "  packageName=com.microsoft.launcher"
	pkg_nm="$(pm resolve-activity -a "$intent_act" -c "$intent_cat" | grep packageName | head -1 | cut -d= -f2)"
	# /data/dalvik-cache/arm64/system@priv-app@OPLauncher2@OPLauncher2.apk@classes.dex 16M/31M  53.2%
	# /data/dalvik-cache/arm64/system@priv-app@OPLauncher2@OPLauncher2.apk@classes.vdex 120K/120K  100%
	# /system/priv-app/OPLauncher2/OPLauncher2.apk 14M/30M  46.1%
	fscc_add_apk "$pkg_nm"
	fscc_add_dex "$pkg_nm"
}

fscc_add_app_ime() {
	# "      packageName=com.baidu.input_yijia"
	pkg_nm="$(ime list | grep packageName | head -1 | cut -d= -f2)"
	# /data/dalvik-cache/arm/system@app@baidushurufa@baidushurufa.apk@classes.dex 5M/17M  33.1%
	# /data/dalvik-cache/arm/system@app@baidushurufa@baidushurufa.apk@classes.vdex 2M/7M  28.1%
	# /system/app/baidushurufa/baidushurufa.apk 1M/28M  5.71%
	# pin apk file in memory is not valuable
	fscc_add_dex "$pkg_nm"
}

# $1:package_name
fscc_add_apex_lib() { fscc_add_obj "$(find /apex -name "$1" | head -1)"; }

# After appending fscc_file_list
# Multiple parameters, cannot be warped by ""
fscc_start() { ${modpath}system/bin/fscache-ctrl -fdlb0 $fscc_file_list; }

fscc_stop() { killall -9 fscache-ctrl; }

# Return:status
fscc_status() {
	# Get the correct value after waiting for fscc loading files
	sleep 2
	[[ "$(pgrep -f "fscache-ctrl")" ]] && echo "Running $(cat /proc/meminfo | grep Mlocked | cut -d: -f2 | tr -d ' ') in cache." || echo "Not running."
}

# Run FSCC (similar to PinnerService, Mlock(Unevictable) 200~350MB)
notif_start
fscc_add_obj "$sys_frm/telephony-common.jar"
fscc_add_obj "$sys_frm/qcnvitems.jar"
fscc_add_obj "$sys_frm/oat"
fscc_add_obj "$sys_frm/arm64"
fscc_add_obj "$sys_frm/miui-okhttp.jar"
fscc_add_obj "/system/bin/surfaceflinger"
fscc_add_obj "/system/bin/servicemanager"
fscc_add_obj "$sys_lib/libbinder.so"
fscc_add_obj "$sys_lib/libgui.so"
fscc_add_obj "$sys_lib/libsurfaceflinger.so"
fscc_add_obj "$sys_lib/libandroid_servers.so"
fscc_add_obj "$sys_lib/libandroid_runtime.so"
fscc_add_obj "$sys_lib/libandroidfw.so"
fscc_add_obj "$sys_lib/libandroid.so"
fscc_add_obj "$sys_lib/libhwui.so"
fscc_add_obj "$sys_lib/libjpeg.so"
fscc_add_obj "$sys_lib/libinput.so"
fscc_add_obj "$sys_lib/libinputreader.so"
fscc_add_obj "$sys_lib/libvulkan.so"
fscc_add_obj "$sys_lib/libGLESv3.so"
fscc_add_obj "$sys_lib/libRScpp.so"
fscc_add_obj "$sys_lib/libRS.so"
fscc_add_obj "$sys_lib/libRS_internal.so"
fscc_add_obj "$sys_lib/libbcinfo.so"
fscc_add_obj "$sys_lib/libRSDriver.so"
fscc_add_obj "$sys_lib/libRSCpuRef.so"
fscc_add_obj "$sys_lib/libblas.so"
fscc_add_obj "$vdr_lib/libssc.so"
fscc_add_obj "$vdr_lib/libgsl.so"
fscc_add_obj "$vdr_lib/sensors.ssc.so"
fscc_add_obj "$vdr_lib/libCB.so"
fscc_add_obj "$vdr_lib/librs_adreno.so"
fscc_add_apex_lib "okhttp.jar"
fscc_add_apex_lib "bouncycastle.jar"
# Do not pin too many files on low memory devices
[[ "$total_ram" -ge "2048" ]] && {
	fscc_add_apk "com.android.systemui"
	fscc_add_dex "com.android.systemui"
}
[[ "$total_ram" -ge "4096" ]] && {
	fscc_add_app_home
	fscc_add_app_ime
}
fscc_stop
fscc_start
notif_end