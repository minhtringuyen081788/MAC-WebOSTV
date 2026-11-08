#!/usr/bin/env bash
# Tối ưu TV Sony (Android TV / Google TV) qua ADB.
# Không cần root, không flash firmware, mọi thay đổi đều hoàn tác được bằng lệnh "restore".
# Chạy được trên macOS (bash 3.2), Linux và Git Bash trên Windows.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_FILE="${PKG_FILE:-$SCRIPT_DIR/packages-disable.txt}"
STATE_DIR="$SCRIPT_DIR/state"
TAILSCALE_PKG="com.tailscale.ipn"

# Những gói tuyệt đối không tắt: tắt nhầm có thể làm TV mất màn hình chính,
# mất cửa hàng ứng dụng hoặc mất kết nối Tailscale tới máy chủ.
PROTECTED="
com.google.android.tvlauncher
com.google.android.apps.tv.launcherx
com.google.android.leanbacklauncher
com.google.android.tungsten.setupwraith
com.google.android.gms
com.google.android.gsf
com.android.vending
com.android.tv.settings
com.android.providers.settings
com.android.packageinstaller
com.google.android.packageinstaller
com.sony.dtv.tvx
$TAILSCALE_PKG
"

usage() {
  cat <<EOF
Cách dùng: $(basename "$0") <IP_TV[:cổng]> <lệnh>

Lệnh:
  scan            Xem thông tin TV: model, RAM, app đang ngốn bộ nhớ, gói nào sẽ bị tắt
  apply           Tắt các app trong packages-disable.txt, giảm hiệu ứng chuyển cảnh, dọn cache
  restore         Bật lại toàn bộ app đã tắt và trả hiệu ứng về mặc định
  vpn-always-on   Cho Tailscale tự bật lại sau mỗi lần TV khởi động (cần cài Tailscale trước)
  reboot          Khởi động lại TV

Ví dụ:
  $(basename "$0") 192.168.1.50 scan      # TV cùng mạng với máy tính
  $(basename "$0") 100.101.102.103 apply  # TV ở nhà khách, đi qua Tailscale
EOF
  exit 1
}

die() { echo "Lỗi: $*" >&2; exit 1; }

[ $# -eq 2 ] || usage
command -v adb >/dev/null 2>&1 || die "chưa cài adb. Mac: brew install android-platform-tools | Windows/Linux: tải 'SDK Platform-Tools' của Google."
[ -f "$PKG_FILE" ] || die "không thấy file danh sách $PKG_FILE"

TARGET="$1"
CMD="$2"
case "$TARGET" in
  *:*) ;;
  *) TARGET="$TARGET:5555" ;;
esac
STATE_FILE="$STATE_DIR/disabled-$(echo "$TARGET" | tr ':.' '__').txt"

tv() { adb -s "$TARGET" shell "$@" 2>&1 | tr -d '\r'; }

connect() {
  adb connect "$TARGET" >/dev/null 2>&1
  state="$(adb -s "$TARGET" get-state 2>/dev/null | tr -d '\r')"
  case "$state" in
    device) echo "Đã kết nối TV $TARGET" ;;
    unauthorized)
      die "TV đang hỏi 'Cho phép gỡ lỗi?'. Bấm 'Luôn cho phép từ máy tính này' trên TV rồi chạy lại lệnh." ;;
    *)
      echo "Không kết nối được TV $TARGET." >&2
      echo "  - TV đã bật 'Gỡ lỗi USB' trong Tuỳ chọn nhà phát triển chưa?" >&2
      echo "  - TV ở mạng khác: máy tính và TV đã cùng đăng nhập Tailscale chưa? Dùng IP 100.x.x.x của TV." >&2
      echo "  - TV đời mới (Android 11+): thử mục 'Gỡ lỗi không dây' và lệnh 'adb pair'." >&2
      exit 1 ;;
  esac
}

# Đọc danh sách gói: bỏ chú thích sau dấu #, bỏ dòng trống.
read_packages() {
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$PKG_FILE" | grep -v '^$'
}

is_protected() {
  echo "$PROTECTED" | grep -qx "$1"
}

load_package_lists() {
  INSTALLED="$(tv pm list packages | sed 's/^package://')"
  DISABLED="$(tv pm list packages -d | sed 's/^package://')"
}

is_installed() { echo "$INSTALLED" | grep -qx "$1"; }
is_disabled()  { echo "$DISABLED"  | grep -qx "$1"; }

set_animations() {
  for key in window_animation_scale transition_animation_scale animator_duration_scale; do
    tv settings put global "$key" "$1" >/dev/null
  done
}

cmd_scan() {
  connect
  load_package_lists
  echo
  echo "== Thông tin TV =="
  echo "Model    : $(tv getprop ro.product.model)"
  echo "Android  : $(tv getprop ro.build.version.release)"
  # Kernel cũ (TV 2015, kernel 3.10) có thể không có MemAvailable: ước lượng bằng MemFree + Cached.
  tv cat /proc/meminfo | awk '
    /^MemTotal:/     { total = $2 }
    /^MemFree:/      { free = $2 }
    /^Cached:/       { cached = $2 }
    /^MemAvailable:/ { avail = $2 }
    END {
      if (avail == "") avail = free + cached
      printf "RAM tổng : %d MB\nRAM trống: %d MB\n", total/1024, avail/1024
    }'
  home="$(tv cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -n 1)"
  case "$home" in */*) ;; *) home="không xác định" ;; esac
  echo "Màn hình chính đang dùng: $home"
  echo "Bản vá bảo mật: $(tv getprop ro.build.version.security_patch)"
  if is_installed "$TAILSCALE_PKG"; then
    echo "Tailscale: đã cài (always-on: $(tv settings get secure always_on_vpn_app))"
  else
    echo "Tailscale: CHƯA cài"
  fi

  echo
  echo "== 15 tiến trình ngốn RAM nhất =="
  tv dumpsys meminfo | sed -n '/Total [PR]SS by process/,/^$/p' | sed -n '2,16p'

  echo
  echo "== Gói trong packages-disable.txt =="
  for pkg in $(read_packages); do
    if is_protected "$pkg"; then
      echo "  [được bảo vệ, sẽ bỏ qua] $pkg"
    elif ! is_installed "$pkg"; then
      echo "  [không có trên TV]        $pkg"
    elif is_disabled "$pkg"; then
      echo "  [đã tắt]                  $pkg"
    else
      echo "  [sẽ tắt khi apply]        $pkg"
    fi
  done

  echo
  echo "== Các gói của Sony trên TV (tự xem xét, thêm vào danh sách nếu chắc chắn không dùng) =="
  echo "$INSTALLED" | grep '^com\.sony\.' | sort | sed 's/^/  /'
}

cmd_apply() {
  connect
  load_package_lists
  mkdir -p "$STATE_DIR"
  echo
  echo "== Tắt ứng dụng thừa =="
  for pkg in $(read_packages); do
    if is_protected "$pkg"; then
      echo "  bỏ qua (được bảo vệ): $pkg"; continue
    fi
    if ! is_installed "$pkg"; then
      echo "  bỏ qua (không có):    $pkg"; continue
    fi
    if is_disabled "$pkg"; then
      echo "  đã tắt từ trước:      $pkg"; continue
    fi
    out="$(tv pm disable-user --user 0 "$pkg")"
    case "$out" in
      *disabled-user*) echo "  ✓ đã tắt:             $pkg"; echo "$pkg" >> "$STATE_FILE" ;;
      *)               echo "  ✗ không tắt được:     $pkg ($out)" ;;
    esac
  done

  echo
  echo "== Giảm hiệu ứng chuyển cảnh xuống 0.5x (menu mở nhanh hơn) =="
  set_animations 0.5
  echo "  ✓ xong"

  echo
  echo "== Dọn cache và đóng app chạy nền =="
  tv pm trim-caches 999G >/dev/null
  tv am kill-all >/dev/null
  echo "  ✓ xong"

  echo
  echo "Hoàn tất. Nên khởi động lại TV: $(basename "$0") $1 reboot"
  echo "Muốn hoàn tác: $(basename "$0") $1 restore"
}

cmd_restore() {
  connect
  load_package_lists
  echo
  echo "== Bật lại ứng dụng =="
  candidates="$(read_packages; [ -f "$STATE_FILE" ] && cat "$STATE_FILE")"
  for pkg in $(echo "$candidates" | sort -u); do
    if is_disabled "$pkg"; then
      tv pm enable "$pkg" >/dev/null && echo "  ✓ đã bật lại: $pkg"
    fi
  done
  set_animations 1
  echo "  ✓ hiệu ứng chuyển cảnh về mặc định 1x"
  rm -f "$STATE_FILE"
  echo
  echo "Hoàn tất. Nên khởi động lại TV: $(basename "$0") $1 reboot"
}

cmd_vpn_always_on() {
  connect
  load_package_lists
  sdk="$(tv getprop ro.build.version.sdk)"
  if [ "${sdk:-0}" -lt 26 ] 2>/dev/null; then
    die "TV chạy Android API $sdk (dưới Android 8.0), Tailscale không hỗ trợ. Xem Cách A / Cách B trong README."
  fi
  is_installed "$TAILSCALE_PKG" || die "TV chưa cài Tailscale. Mở Google Play trên TV, cài Tailscale và đăng nhập trước."
  tv settings put secure always_on_vpn_app "$TAILSCALE_PKG" >/dev/null
  tv settings put secure always_on_vpn_lockdown 0 >/dev/null
  echo "Đã đặt Tailscale tự bật khi TV khởi động (always_on_vpn_app = $(tv settings get secure always_on_vpn_app))."
  echo "Khởi động lại TV rồi kiểm tra TV có hiện 'Connected' trong trang quản trị Tailscale."
}

case "$CMD" in
  scan)          cmd_scan ;;
  apply)         cmd_apply "$1" ;;
  restore)       cmd_restore "$1" ;;
  vpn-always-on) cmd_vpn_always_on ;;
  reboot)        connect; adb -s "$TARGET" reboot; echo "TV đang khởi động lại." ;;
  *)             usage ;;
esac
